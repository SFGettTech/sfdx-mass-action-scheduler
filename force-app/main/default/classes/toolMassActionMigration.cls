/**
 * Author        : Josh Gettman
 * Date          : 2026-08-03
 * Description   : Migrates Mass Action Scheduler configuration data from the installed
 *                 MANAGED package objects (namespace-prefixed) into the UN-NAMESPACED
 *                 source objects deployed by this fork, as part of a full source
 *                 replacement of the managed package. Run once per target org AFTER the
 *                 un-namespaced source is deployed and BEFORE uninstalling the managed
 *                 package (uninstalling deletes the managed data that is the migration
 *                 source of truth).
 *
 *                 Copies Mass_Action_Configuration__c parents and their
 *                 Mass_Action_Mapping__c master-detail children. Fields are copied by
 *                 INTERSECTION: for each writable field on the un-namespaced target
 *                 object, the value is copied only if the managed object also exposes
 *                 that field as namespace__field. This means fields that exist only on
 *                 the newer un-namespaced object (e.g. Mapping_Type__c, Source_Value__c)
 *                 are never read from the older managed package and simply take their
 *                 default values on the migrated records.
 *
 *                 All managed access is dynamic, so this class compiles and deploys
 *                 whether or not the managed package is installed, and continues to
 *                 compile after the package is uninstalled.
 *
 *                 Idempotent: configurations upsert on the unique external id
 *                 DeveloperName__c; child mappings are deleted and rebuilt per migrated
 *                 configuration, so the migration is safe to re-run.
 *
 *                 Run from anonymous apex, e.g.:
 *                     // dry run first (no DML, logs counts):
 *                     System.debug( toolMassActionMigration.migrate( 'mas', false ) );
 *                     // then commit:
 *                     System.debug( toolMassActionMigration.migrate( 'mas', true ) );
 *
 *                 Uses 'without sharing' (documented exception to the with-sharing
 *                 default) so the migration captures every configuration record
 *                 regardless of the running user's record sharing; run it as an
 *                 administrator.
 *
 *                 Scope note: MAS configurations are few by design, so this runs
 *                 synchronously. If an org held an unusually large number of records,
 *                 wrap the write phase in a Batchable.
 * Version       : 1.1
 * Modification Log:
 * Ver  | Date       | Author        | Modification
 * 1.0  | 2026-08-03 | Josh Gettman  | Initial version
 * 1.1  | 2026-08-03 | Josh Gettman  | ManagedPackageReader treats a blank namespace as
 *      |            |               | "no prefix" so the field-intersection logic can be
 *      |            |               | covered by tests without the managed package
 *      |            |               | installed. migrate() still rejects a blank
 *      |            |               | namespace, so production behaviour is unchanged.
 * 1.1  | 2026-08-07 | Josh Gettman  | Passed AccessLevel.SYSTEM_MODE to every
 *      |            |               | Database.query/upsert/insert/delete call. At API
 *      |            |               | 67.0 these default to user mode, which made the
 *      |            |               | migration depend on the running user's FLS over
 *      |            |               | both the managed and the un-namespaced objects.
 * 1.1  | 2026-08-25 | Josh Gettman  | Removed the last FLS dependency from the reader.
 *      |            |               | Describe is user mode at API 67.0, so
 *      |            |               | isCreateable() was silently dropping every field
 *      |            |               | the running user had no FLS on -- including the
 *      |            |               | external id, which then threw "SObject row was
 *      |            |               | retrieved via SOQL without querying the requested
 *      |            |               | field: DeveloperName__c". Field selection is now
 *      |            |               | structural and the external id is always selected.
 */
public without sharing class toolMassActionMigration {

    private static final String CONFIG_OBJECT = 'Mass_Action_Configuration__c';
    private static final String MAPPING_OBJECT = 'Mass_Action_Mapping__c';
    private static final String CONFIG_EXTERNAL_ID = 'DeveloperName__c';
    private static final String MAPPING_PARENT_FIELD = 'Mass_Action_Configuration__c';

    // Injectable reader so the write path can be unit tested without the managed
    // package being installed. Default implementation reads the managed objects.
    @TestVisible
    private static ManagedDataReader reader = new ManagedPackageReader();

    /**
     * Migrates managed configurations and mappings into the un-namespaced objects.
     *
     * @param managedNamespace
     *      The installed managed package namespace WITHOUT trailing underscores
     *      (see Setup > Installed Packages; commonly 'mas').
     * @param commitChanges
     *      When false, performs a dry run: builds the target records and reports
     *      counts without any DML. When true, commits the migration.
     * @return MigrationResult with counts, errors, and a human-readable message.
     */
    public static MigrationResult migrate( String managedNamespace, Boolean commitChanges ) {

        MigrationResult result = new MigrationResult();
        result.committed = false;

        if ( String.isBlank( managedNamespace ) ) {
            result.message = 'managedNamespace is blank. Provide the installed package namespace ' +
                '(Setup > Installed Packages), e.g. \'mas\'.';
            result.errors.add( result.message );
            return result;
        }

        SObjectType targetConfigType = Schema.getGlobalDescribe().get( CONFIG_OBJECT );
        SObjectType targetMappingType = Schema.getGlobalDescribe().get( MAPPING_OBJECT );

        if ( targetConfigType == null || targetMappingType == null ) {
            result.message = 'Un-namespaced target objects not found (' + CONFIG_OBJECT + ' / ' +
                MAPPING_OBJECT + '). Deploy the fork source before running the migration.';
            result.errors.add( result.message );
            return result;
        }

        List<ManagedConfig> sourceConfigs;
        try {
            sourceConfigs = reader.readManagedConfigs( managedNamespace );
        } catch ( Exception readException ) {
            result.message = 'Failed to read managed configurations under namespace \'' +
                managedNamespace + '\': ' + readException.getTypeName() + ': ' + readException.getMessage();
            result.errors.add( result.message );
            return result;
        }

        if ( sourceConfigs == null || sourceConfigs.isEmpty() ) {
            result.message = 'No managed configurations found under namespace \'' + managedNamespace +
                '\'. Nothing to migrate. (Verify the namespace and that the managed package is installed.)';
            return result;
        }

        // Build target configuration records, skipping any with a blank external id
        // (cannot upsert-match a null external id, so we do not risk silent duplicates).
        List<SObject> targetConfigs = new List<SObject>();
        List<ManagedConfig> migratableConfigs = new List<ManagedConfig>();

        for ( ManagedConfig sc : sourceConfigs ) {

            if ( String.isBlank( sc.developerName ) ) {
                result.errors.add( 'Skipped a configuration with a blank ' + CONFIG_EXTERNAL_ID +
                    ' (Name=' + sc.configValues.get( 'Name' ) + '); cannot upsert without the external id.' );
                continue;
            }

            SObject tgt = targetConfigType.newSObject();
            for ( String fieldApiName : sc.configValues.keySet() ) {
                tgt.put( fieldApiName, sc.configValues.get( fieldApiName ) );
            }
            targetConfigs.add( tgt );
            migratableConfigs.add( sc );

        }

        result.configsProcessed = targetConfigs.size();
        Integer mappingCount = 0;
        for ( ManagedConfig sc : migratableConfigs ) {
            mappingCount += ( sc.mappingValues == null ? 0 : sc.mappingValues.size() );
        }
        result.mappingsProcessed = mappingCount;

        if ( commitChanges != true ) {
            result.message = 'DRY RUN (commitChanges=false). Would upsert ' + result.configsProcessed +
                ' configuration(s) and rebuild ' + result.mappingsProcessed + ' mapping(s). No DML performed.';
            return result;
        }

        // ---- Upsert configurations on the external id ----
        Schema.SObjectField extIdField =
            targetConfigType.getDescribe().fields.getMap().get( CONFIG_EXTERNAL_ID.toLowerCase() );

        List<Database.UpsertResult> upsertResults = Database.upsert( targetConfigs, extIdField, false, AccessLevel.SYSTEM_MODE );
        for ( Integer i = 0; i < upsertResults.size(); i++ ) {
            if ( !upsertResults[i].isSuccess() ) {
                for ( Database.Error e : upsertResults[i].getErrors() ) {
                    result.errors.add( 'Config row ' + i + ' (' +
                        migratableConfigs[i].developerName + '): ' + e.getStatusCode() + ' - ' + e.getMessage() );
                }
            }
        }

        // ---- Resolve target parent ids by external id ----
        Map<String, Id> targetConfigIdByDevName = new Map<String, Id>();
        for ( SObject tc : Database.query(
                'SELECT Id, ' + CONFIG_EXTERNAL_ID + ' FROM ' + CONFIG_OBJECT +
                ' WHERE ' + CONFIG_EXTERNAL_ID + ' != null', AccessLevel.SYSTEM_MODE ) ) {
            targetConfigIdByDevName.put( (String) tc.get( CONFIG_EXTERNAL_ID ), (Id) tc.get( 'Id' ) );
        }

        // ---- Rebuild child mappings (delete then insert per migrated config) ----
        Set<Id> migratedParentIds = new Set<Id>();
        for ( ManagedConfig sc : migratableConfigs ) {
            Id parentId = targetConfigIdByDevName.get( sc.developerName );
            if ( parentId != null ) {
                migratedParentIds.add( parentId );
            }
        }

        if ( !migratedParentIds.isEmpty() ) {
            List<SObject> existingMappings = Database.query(
                'SELECT Id FROM ' + MAPPING_OBJECT +
                ' WHERE ' + MAPPING_PARENT_FIELD + ' IN :migratedParentIds', AccessLevel.SYSTEM_MODE );
            if ( !existingMappings.isEmpty() ) {
                List<Database.DeleteResult> deleteResults = Database.delete( existingMappings, false, AccessLevel.SYSTEM_MODE );
                for ( Integer i = 0; i < deleteResults.size(); i++ ) {
                    if ( !deleteResults[i].isSuccess() ) {
                        for ( Database.Error e : deleteResults[i].getErrors() ) {
                            result.errors.add( 'Mapping delete row ' + i + ': ' + e.getStatusCode() + ' - ' + e.getMessage() );
                        }
                    }
                }
            }
        }

        List<SObject> targetMappings = new List<SObject>();
        for ( ManagedConfig sc : migratableConfigs ) {

            Id parentId = targetConfigIdByDevName.get( sc.developerName );
            if ( parentId == null ) {
                result.errors.add( 'No migrated parent resolved for ' + CONFIG_EXTERNAL_ID + '=' +
                    sc.developerName + '; its mappings were skipped.' );
                continue;
            }

            if ( sc.mappingValues == null ) {
                continue;
            }

            for ( Map<String, Object> mv : sc.mappingValues ) {
                SObject tgtMap = targetMappingType.newSObject();
                tgtMap.put( MAPPING_PARENT_FIELD, parentId );
                for ( String fieldApiName : mv.keySet() ) {
                    tgtMap.put( fieldApiName, mv.get( fieldApiName ) );
                }
                targetMappings.add( tgtMap );
            }

        }

        if ( !targetMappings.isEmpty() ) {
            List<Database.SaveResult> insertResults = Database.insert( targetMappings, false, AccessLevel.SYSTEM_MODE );
            for ( Integer i = 0; i < insertResults.size(); i++ ) {
                if ( !insertResults[i].isSuccess() ) {
                    for ( Database.Error e : insertResults[i].getErrors() ) {
                        result.errors.add( 'Mapping insert row ' + i + ': ' + e.getStatusCode() + ' - ' + e.getMessage() );
                    }
                }
            }
        }

        result.committed = true;
        result.message = 'Migration committed. Configurations upserted: ' + result.configsProcessed +
            ', mappings rebuilt: ' + targetMappings.size() + ', errors: ' + result.errors.size() + '.';
        return result;
    }

    // ------------------------------------------------------------------------
    // Injectable reader interface + default managed-package implementation
    // ------------------------------------------------------------------------

    public interface ManagedDataReader {
        List<ManagedConfig> readManagedConfigs( String managedNamespace );
    }

    /**
     * Default reader. Dynamically discovers the copyable fields (intersection of the
     * un-namespaced target object's createable fields and the managed object's fields)
     * and reads the managed records, returning ManagedConfig DTOs keyed by TARGET field
     * API names so the writer is namespace-agnostic.
     */
    public class ManagedPackageReader implements ManagedDataReader {

        public List<ManagedConfig> readManagedConfigs( String managedNamespace ) {

            // A blank namespace means "no prefix", which makes this reader read the
            // un-namespaced objects directly. migrate() rejects a blank namespace before it
            // can ever reach here, so in production `ns` is always the managed prefix. The
            // blank form exists so the field-intersection logic below can be exercised by
            // tests in an org where the managed package is not, and cannot be, installed.
            String ns = ( String.isBlank( managedNamespace ) ? '' : managedNamespace + '__' );

            SObjectType managedConfigType = Schema.getGlobalDescribe().get( ns + CONFIG_OBJECT );
            SObjectType managedMappingType = Schema.getGlobalDescribe().get( ns + MAPPING_OBJECT );

            if ( managedConfigType == null || managedMappingType == null ) {
                // Managed package not installed under this namespace; nothing to read.
                return new List<ManagedConfig>();
            }

            Map<String, SObjectField> managedConfigFields = managedConfigType.getDescribe().fields.getMap();
            Map<String, SObjectField> managedMappingFields = managedMappingType.getDescribe().fields.getMap();

            // targetFieldApiName -> managed SELECT token (standard 'Name' has no namespace)
            Map<String, String> configTokens = buildCopyTokens(
                CONFIG_OBJECT, ns, managedConfigFields, true );
            Map<String, String> mappingTokens = buildCopyTokens(
                MAPPING_OBJECT, ns, managedMappingFields, false );

            // ---- Read managed configurations ----
            // The external id is structural, not one of the optionally-copied values:
            // the writer upserts on it, so it is selected explicitly and unconditionally
            // rather than being left to the field intersection. A Set de-duplicates it
            // against the copy tokens, which normally contain it as well.
            String devNameToken = ns + CONFIG_EXTERNAL_ID;
            Set<String> configSelect = new Set<String>{ 'Id', devNameToken };
            configSelect.addAll( configTokens.values() );

            String configQuery = 'SELECT ' + String.join( new List<String>( configSelect ), ', ' ) +
                ' FROM ' + ns + CONFIG_OBJECT;
            List<SObject> managedConfigs = Database.query( configQuery, AccessLevel.SYSTEM_MODE );

            // ---- Read managed mappings, grouped by managed parent id ----
            String parentToken = ns + MAPPING_PARENT_FIELD;
            Set<String> mappingSelect = new Set<String>{ 'Id', parentToken };
            mappingSelect.addAll( mappingTokens.values() );

            String mappingQuery = 'SELECT ' + String.join( new List<String>( mappingSelect ), ', ' ) +
                ' FROM ' + ns + MAPPING_OBJECT;
            List<SObject> managedMappings = Database.query( mappingQuery, AccessLevel.SYSTEM_MODE );

            Map<Id, List<SObject>> mappingsByParent = new Map<Id, List<SObject>>();
            for ( SObject m : managedMappings ) {
                Id parentId = (Id) m.get( parentToken );
                if ( !mappingsByParent.containsKey( parentId ) ) {
                    mappingsByParent.put( parentId, new List<SObject>() );
                }
                mappingsByParent.get( parentId ).add( m );
            }

            // ---- Translate to target-keyed DTOs ----
            List<ManagedConfig> results = new List<ManagedConfig>();

            for ( SObject sc : managedConfigs ) {

                ManagedConfig mc = new ManagedConfig();
                mc.developerName = (String) sc.get( devNameToken );

                mc.configValues = new Map<String, Object>();
                for ( String targetField : configTokens.keySet() ) {
                    mc.configValues.put( targetField, sc.get( configTokens.get( targetField ) ) );
                }

                mc.mappingValues = new List<Map<String, Object>>();
                List<SObject> children = mappingsByParent.get( (Id) sc.get( 'Id' ) );
                if ( children != null ) {
                    for ( SObject child : children ) {
                        Map<String, Object> mv = new Map<String, Object>();
                        for ( String targetField : mappingTokens.keySet() ) {
                            mv.put( targetField, child.get( mappingTokens.get( targetField ) ) );
                        }
                        mc.mappingValues.add( mv );
                    }
                }

                results.add( mc );
            }

            return results;
        }

        /**
         * Builds a map of un-namespaced target field API name -> managed SELECT token,
         * for every writable field on the target object (custom fields, plus the
         * standard Name when allowed) that also exists on the managed object. The
         * master-detail parent field is always excluded (handled separately by the
         * writer). Formula and auto-number fields are excluded because they cannot be
         * written; other standard and system fields are excluded by the isCustom check.
         * The selection is intentionally FLS-independent -- see the comment on the
         * exclusions below.
         */
        private Map<String, String> buildCopyTokens(
                String targetObjectApiName, String ns,
                Map<String, SObjectField> managedFields, Boolean allowStandardName ) {

            Map<String, String> tokens = new Map<String, String>();

            SObjectType targetType = Schema.getGlobalDescribe().get( targetObjectApiName );
            Map<String, SObjectField> targetFields = targetType.getDescribe().fields.getMap();

            for ( String key : targetFields.keySet() ) {

                DescribeFieldResult dfr = targetFields.get( key ).getDescribe();
                String apiName = dfr.getName();

                // Structural exclusions only. Deliberately NOT isCreateable(): at API 67.0
                // describe is evaluated in user mode, so isCreateable() also reports the
                // running user's FLS. In an org where Mass_Action_Admin is not assigned to
                // the running user, that silently emptied this map, which dropped fields
                // from the migration and left the external id out of the SELECT list. Every
                // query and DML in this class runs SYSTEM_MODE, so the field set it copies
                // must not depend on FLS either. Formula and auto-number fields are not
                // writable and are excluded structurally instead; neither object carries a
                // roll-up summary field, which Apex describe cannot identify directly.
                if ( dfr.isCalculated() || dfr.isAutoNumber() ) {
                    continue;
                }
                if ( apiName == MAPPING_PARENT_FIELD ) {
                    continue; // master-detail parent handled by the writer
                }

                Boolean isStandardName = ( apiName.equalsIgnoreCase( 'Name' ) );
                if ( isStandardName && !allowStandardName ) {
                    continue;
                }
                if ( !dfr.isCustom() && !isStandardName ) {
                    continue; // skip other standard/system fields
                }

                // Managed select token: standard Name has no namespace; custom fields do.
                String managedToken = isStandardName ? 'Name' : ( ns + apiName );

                if ( managedFields.containsKey( managedToken.toLowerCase() ) ) {
                    tokens.put( apiName, managedToken );
                }
            }

            return tokens;
        }

    }

    // ------------------------------------------------------------------------
    // DTOs (kept at end of file per standards)
    // ------------------------------------------------------------------------

    public class ManagedConfig {
        public String developerName;
        public Map<String, Object> configValues;          // keyed by TARGET field api name
        public List<Map<String, Object>> mappingValues;   // each keyed by TARGET field api name
    }

    public class MigrationResult {
        public Integer configsProcessed = 0;
        public Integer mappingsProcessed = 0;
        public Boolean committed = false;
        public String message = '';
        public List<String> errors = new List<String>();

        public override String toString() {
            return message + ( errors.isEmpty() ? '' : ' | Errors: ' + String.join( errors, '; ' ) );
        }
    }

}
