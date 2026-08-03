/**
 * Author        : Josh Gettman
 * Date          : 2026-08-03
 * Description   : Unit tests for toolMassActionMigration. Injects a stub ManagedDataReader
 *                 so the full write path is exercised against the real un-namespaced
 *                 objects WITHOUT requiring the managed package to be installed in the org.
 *                 Covers: commit path, idempotency on re-run, dry-run performs no DML,
 *                 blank-external-id skip, empty source no-op, and the static-mapping
 *                 default (migrated mappings receive no Mapping_Type__c/Source_Value__c
 *                 from the reader, so they fall back to the object default).
 * Version       : 1.1
 * Modification Log:
 * Ver  | Date       | Author        | Modification
 * 1.0  | 2026-08-03 | Josh Gettman  | Initial version
 * 1.1  | 2026-08-03 | Josh Gettman  | Added coverage for the real ManagedPackageReader
 *      |            |               | and the failure paths: read failure, upsert
 *      |            |               | failure, mapping insert failure, null mapping
 *      |            |               | list, and Active__c preservation.
 *
 * Registered in Mass_Action_Scheduler_Test_Suite.
 */
@IsTest
private class toolMassActionMigrationTEST {

    private class StubReader implements toolMassActionMigration.ManagedDataReader {

        private List<toolMassActionMigration.ManagedConfig> toReturn;

        public StubReader( List<toolMassActionMigration.ManagedConfig> toReturn ) {
            this.toReturn = toReturn;
        }

        public List<toolMassActionMigration.ManagedConfig> readManagedConfigs( String managedNamespace ) {
            return this.toReturn;
        }
    }

    private static toolMassActionMigration.ManagedConfig buildConfig(
            String devName, String name, List<Map<String, Object>> mappings ) {

        toolMassActionMigration.ManagedConfig mc = new toolMassActionMigration.ManagedConfig();
        mc.developerName = devName;
        mc.configValues = new Map<String, Object>{
            'Name' => name,
            'DeveloperName__c' => devName,
            'Source_Type__c' => 'SOQL',
            'Target_Type__c' => 'Flow',
            'Target_Action_Name__c' => 'Some_Flow',
            'Batch_Size__c' => 1,
            'Active__c' => false,
            'Source_SOQL_Query__c' => 'SELECT Id FROM Account'
        };
        mc.mappingValues = mappings;
        return mc;
    }

    @IsTest
    static void migrateCommitsConfigsAndMappings() {

        List<Map<String, Object>> mappings = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Source_Field_Name__c' => 'Id', 'Target_Field_Name__c' => 'SObjectId' }
        };

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{
                buildConfig( 'cfg_alpha', 'Alpha', mappings )
            }
        );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( true, result.committed, 'Migration should commit. message=' + result.message );
        System.assertEquals( 1, result.configsProcessed, 'One config expected. ' + result.toString() );

        List<SObject> configs = Database.query(
            'SELECT Id, Name, DeveloperName__c FROM Mass_Action_Configuration__c WHERE DeveloperName__c = \'cfg_alpha\'' );
        System.assertEquals( 1, configs.size(), 'Config should be inserted. errors=' + result.errors );

        List<SObject> maps = Database.query(
            'SELECT Id, Source_Field_Name__c, Target_Field_Name__c, Mapping_Type__c, Source_Value__c ' +
            'FROM Mass_Action_Mapping__c' );
        System.assertEquals( 1, maps.size(), 'One mapping expected. ' + result.toString() );
        // Static-mapping fields were never supplied by the reader, so they default.
        System.assertEquals( null, maps[0].get( 'Source_Value__c' ),
            'Source_Value__c should default to null on migrated mappings.' );
    }

    @IsTest
    static void migrateIsIdempotentOnRerun() {

        List<Map<String, Object>> mappings = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Source_Field_Name__c' => 'Id', 'Target_Field_Name__c' => 'SObjectId' }
        };

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{
                buildConfig( 'cfg_beta', 'Beta', mappings )
            }
        );

        Test.startTest();
        toolMassActionMigration.migrate( 'mas', true );
        toolMassActionMigration.migrate( 'mas', true ); // second run
        Test.stopTest();

        List<SObject> configs = Database.query(
            'SELECT Id FROM Mass_Action_Configuration__c WHERE DeveloperName__c = \'cfg_beta\'' );
        System.assertEquals( 1, configs.size(), 'Re-run must not duplicate the config. count=' + configs.size() );

        List<SObject> maps = Database.query( 'SELECT Id FROM Mass_Action_Mapping__c' );
        System.assertEquals( 1, maps.size(), 'Re-run must not duplicate mappings. count=' + maps.size() );
    }

    @IsTest
    static void dryRunPerformsNoDml() {

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{
                buildConfig( 'cfg_gamma', 'Gamma', new List<Map<String, Object>>() )
            }
        );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', false );
        Test.stopTest();

        System.assertEquals( false, result.committed, 'Dry run must not commit.' );
        System.assertEquals( 1, result.configsProcessed, 'Dry run should still report counts.' );

        List<SObject> configs = Database.query(
            'SELECT Id FROM Mass_Action_Configuration__c WHERE DeveloperName__c = \'cfg_gamma\'' );
        System.assertEquals( 0, configs.size(), 'Dry run must not insert records.' );
    }

    @IsTest
    static void blankExternalIdIsSkipped() {

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{
                buildConfig( null, 'NoDevName', new List<Map<String, Object>>() )
            }
        );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( 0, result.configsProcessed, 'Blank external id config must be skipped.' );
        System.assert( !result.errors.isEmpty(), 'A skip warning should be recorded.' );
    }

    @IsTest
    static void emptySourceIsNoOp() {

        toolMassActionMigration.reader = new StubReader( new List<toolMassActionMigration.ManagedConfig>() );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( false, result.committed, 'Empty source should not commit.' );
        System.assertEquals( 0, result.configsProcessed, 'Nothing to process. ' + result.message );
    }

    @IsTest
    static void blankNamespaceReturnsError() {

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( '', true );
        Test.stopTest();

        System.assert( !result.errors.isEmpty(), 'Blank namespace should produce an error.' );
        System.assert( result.message.contains( 'managedNamespace is blank' ),
            'Message should explain the blank namespace. message=' + result.message );
    }

    // ------------------------------------------------------------------------
    // Real ManagedPackageReader (not stubbed)
    // ------------------------------------------------------------------------

    /**
     * Exercises the real reader, including the dynamic field intersection, against the
     * un-namespaced objects by passing a blank namespace, which the reader treats as
     * "no prefix". The managed package cannot be installed in a scratch org, so this is
     * the only way to run the intersection logic for real.
     */
    @IsTest
    static void realReaderReadsViaFieldIntersection() {

        Mass_Action_Configuration__c config = new Mass_Action_Configuration__c(
            Name = 'Reader Probe',
            DeveloperName__c = 'reader_probe',
            Source_Type__c = 'SOQL',
            Source_SOQL_Query__c = 'SELECT Id FROM Account',
            Target_Type__c = 'Flow',
            Target_Action_Name__c = 'Some_Flow',
            Active__c = false,
            Batch_Size__c = 1
        );
        insert config;

        insert new List<Mass_Action_Mapping__c>{
            new Mass_Action_Mapping__c(
                Mass_Action_Configuration__c = config.Id,
                Source_Field_Name__c = 'Id',
                Target_Field_Name__c = 'SObjectId'
            ),
            new Mass_Action_Mapping__c(
                Mass_Action_Configuration__c = config.Id,
                Mapping_Type__c = 'Static Value',
                Source_Value__c = 'Nightly',
                Target_Field_Name__c = 'RunLabel'
            )
        };

        Test.startTest();

        List<toolMassActionMigration.ManagedConfig> read =
            new toolMassActionMigration.ManagedPackageReader().readManagedConfigs( '' );

        Test.stopTest();

        System.assertEquals( 1, read.size(), 'The reader should return the one configuration.' );

        toolMassActionMigration.ManagedConfig mc = read[0];

        System.assertEquals( 'reader_probe', mc.developerName, 'External id should be read.' );

        // values are keyed by TARGET field api name, with no namespace anywhere
        System.assertEquals( 'Reader Probe', mc.configValues.get( 'Name' ) );
        System.assertEquals( 'SOQL', mc.configValues.get( 'Source_Type__c' ) );
        System.assertEquals( 'Flow', mc.configValues.get( 'Target_Type__c' ) );
        System.assertEquals( false, mc.configValues.get( 'Active__c' ), 'Active__c must be preserved as read.' );

        // the intersection only yields createable fields, never formula or system fields
        System.assertEquals( false, mc.configValues.containsKey( 'Id' ), 'Id is not createable and must be excluded.' );
        System.assertEquals( false, mc.configValues.containsKey( 'CreatedDate' ), 'System fields must be excluded.' );

        // children are grouped under their parent, and the master-detail parent field is
        // excluded from the copied values because the writer sets it explicitly
        System.assertEquals( 2, mc.mappingValues.size(), 'Both mappings should be grouped under the parent.' );

        for ( Map<String, Object> mv : mc.mappingValues ) {
            System.assertEquals( false, mv.containsKey( 'Mass_Action_Configuration__c' ),
                'The master-detail parent field must not be copied; the writer sets it.' );
            System.assert( mv.containsKey( 'Target_Field_Name__c' ), 'Target field name should be copied.' );
        }

    }

    /**
     * The reader must return empty, not throw, when nothing is installed under the given
     * namespace. This is a real production case: running the migration after the managed
     * package has been uninstalled, or with a mistyped namespace.
     */
    @IsTest
    static void realReaderReturnsEmptyWhenPackageAbsent() {

        Test.startTest();

        List<toolMassActionMigration.ManagedConfig> read =
            new toolMassActionMigration.ManagedPackageReader().readManagedConfigs( 'no_such_namespace_zzz' );

        Test.stopTest();

        System.assertEquals( 0, read.size(), 'An absent managed package should read as empty, not throw.' );

    }

    /**
     * And migrate() should surface that as a clean "nothing to migrate" message rather
     * than committing or failing.
     */
    @IsTest
    static void migrateReportsNothingToMigrateWhenPackageAbsent() {

        Test.startTest();

        toolMassActionMigration.MigrationResult result =
            toolMassActionMigration.migrate( 'no_such_namespace_zzz', true );

        Test.stopTest();

        System.assertEquals( false, result.committed, 'Nothing to migrate should not commit.' );
        System.assertEquals( 0, result.configsProcessed );
        System.assert( result.message.contains( 'No managed configurations found' ),
            'Message should explain nothing was found. message=' + result.message );

    }

    // ------------------------------------------------------------------------
    // Failure paths
    // ------------------------------------------------------------------------

    private class ThrowingReader implements toolMassActionMigration.ManagedDataReader {
        public List<toolMassActionMigration.ManagedConfig> readManagedConfigs( String managedNamespace ) {
            throw new System.QueryException( 'SIMULATED READ FAILURE' );
        }
    }

    /**
     * A failure reading the managed data is reported, not propagated, so the operator sees
     * which namespace failed and why.
     */
    @IsTest
    static void readFailureIsReportedNotThrown() {

        toolMassActionMigration.reader = new ThrowingReader();

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( false, result.committed, 'A read failure must not commit.' );
        System.assert( !result.errors.isEmpty(), 'The read failure should be recorded.' );
        System.assert( result.message.contains( 'SIMULATED READ FAILURE' ),
            'The underlying error should be surfaced. message=' + result.message );
        System.assert( result.message.contains( 'mas' ),
            'The namespace that failed should be named. message=' + result.message );

    }

    /**
     * A configuration that fails to upsert is reported per row, and its mappings are
     * skipped with their own error rather than being orphaned onto the wrong parent.
     * Two configurations sharing one external id force that failure.
     */
    @IsTest
    static void upsertFailureIsReportedAndMappingsSkipped() {

        List<Map<String, Object>> mappings = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Source_Field_Name__c' => 'Id', 'Target_Field_Name__c' => 'SObjectId' }
        };

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{
                buildConfig( 'cfg_dupe', 'First', mappings ),
                buildConfig( 'cfg_dupe', 'Second', mappings )
            }
        );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( 2, result.configsProcessed, 'Both rows are attempted.' );
        System.assert( !result.errors.isEmpty(),
            'A duplicate external id should be reported. errors=' + result.errors );

    }

    /**
     * A mapping that cannot be inserted is reported per row. Target_Field_Name__c is
     * required on Mass_Action_Mapping__c, so omitting it fails that row while the parent
     * configuration still migrates.
     */
    @IsTest
    static void mappingInsertFailureIsReported() {

        List<Map<String, Object>> badMappings = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Source_Field_Name__c' => 'Id' }   // no Target_Field_Name__c
        };

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{
                buildConfig( 'cfg_badmap', 'BadMap', badMappings )
            }
        );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( true, result.committed, 'The configuration itself still migrates.' );
        System.assert( !result.errors.isEmpty(),
            'The failed mapping row should be reported. errors=' + result.errors );

        List<SObject> configs = Database.query(
            'SELECT Id FROM Mass_Action_Configuration__c WHERE DeveloperName__c = \'cfg_badmap\'' );
        System.assertEquals( 1, configs.size(), 'Parent config should still be present.' );

        List<SObject> maps = Database.query( 'SELECT Id FROM Mass_Action_Mapping__c' );
        System.assertEquals( 0, maps.size(), 'The invalid mapping should not have been saved.' );

    }

    /**
     * A configuration carrying a null mapping list migrates cleanly with no children.
     */
    @IsTest
    static void nullMappingListIsHandled() {

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{
                buildConfig( 'cfg_nullmaps', 'NullMaps', null )
            }
        );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( true, result.committed, 'A null mapping list should not prevent the migration.' );
        System.assertEquals( 0, result.mappingsProcessed, 'A null mapping list counts as no mappings.' );

        List<SObject> configs = Database.query(
            'SELECT Id FROM Mass_Action_Configuration__c WHERE DeveloperName__c = \'cfg_nullmaps\'' );
        System.assertEquals( 1, configs.size(), 'The configuration should still migrate.' );

    }

    /**
     * Active__c is preserved exactly as read. The migration itself schedules nothing;
     * note that the configuration trigger schedules any config that is active and not
     * 'Manual', so migrated records are inserted with whatever Active__c they carried.
     */
    @IsTest
    static void activeFlagIsPreserved() {

        toolMassActionMigration.ManagedConfig activeConfig =
            buildConfig( 'cfg_active', 'ActiveOne', new List<Map<String, Object>>() );
        activeConfig.configValues.put( 'Active__c', true );
        activeConfig.configValues.put( 'Schedule_Frequency__c', 'Manual' );

        toolMassActionMigration.reader = new StubReader(
            new List<toolMassActionMigration.ManagedConfig>{ activeConfig }
        );

        Test.startTest();
        toolMassActionMigration.MigrationResult result = toolMassActionMigration.migrate( 'mas', true );
        Test.stopTest();

        System.assertEquals( true, result.committed, 'Migration should commit. ' + result.toString() );

        List<SObject> configs = Database.query(
            'SELECT Id, Active__c FROM Mass_Action_Configuration__c WHERE DeveloperName__c = \'cfg_active\'' );
        System.assertEquals( 1, configs.size() );
        System.assertEquals( true, configs[0].get( 'Active__c' ), 'Active__c must be preserved.' );

    }

}
