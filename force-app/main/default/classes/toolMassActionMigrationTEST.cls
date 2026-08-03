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
 * Version       : 1.0
 * Modification Log:
 * Ver  | Date       | Author        | Modification
 * 1.0  | 2026-08-03 | Josh Gettman  | Initial version
 *
 * NOTE: Register this class in Mass_Action_Scheduler_Test_Suite so it runs in CI.
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
}
