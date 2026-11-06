/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-08-03
 * Description:  Static (hard-coded) field mappings.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Added buildActionInputs and saveConfiguration
 *     |            |              | coverage for static value mappings.
 * 1.0 | 2026-08-07 | Josh Gettman | Filtered the fixture Report and Folder
 *     |            |              | lookups to NamespacePrefix = null so
 *     |            |              | they do not also match the managed
 *     |            |              | package's copies.
 * 1.0 | 2026-08-07 | Josh Gettman | Pinned this test class to API 66.0 so
 *     |            |              | its own SOQL and DML keep the system-
 *     |            |              | mode default lost at API 67.0.
 * ---------------------------------------------------------------------------
 */
@IsTest
private class MA_EditConfigRestControllerTest {

    @IsTest
    static void test_getObjectsWithInvocableActions_Flow() {

        String operation = 'getObjectsWithInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'Flow'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 0, result.size() );

    }

    @IsTest
    static void test_getObjectsWithInvocableActions_QuickAction() {

        String operation = 'getObjectsWithInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'QuickAction'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );

        System.assertEquals( 1, result.size() );
        System.assertEquals( 'Account', ((Map<String, Object>) result[0]).get( 'value' ) );

    }

    @IsTest
    static void test_getObjectsWithInvocableActions_EmailAlert() {

        String operation = 'getObjectsWithInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'EmailAlert'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );

        System.assertEquals( 1, result.size() );
        System.assertEquals( 'Account', ((Map<String, Object>) result[0]).get( 'value' ) );

    }

    @IsTest
    static void test_getObjectsWithInvocableActions_Apex() {

        String operation = 'getObjectsWithInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'Apex'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );

        System.assertEquals( 0, result.size() );

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_getInvocableActions_Flow() {

        String operation = 'getInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'Flow',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Flow', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Flow', resultAction.get( 'value' ) );

    }

    @IsTest
    static void test_getInvocableActions_QuickAction() {

        String operation = 'getInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'QuickAction',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Quick Action', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Quick_Action', resultAction.get( 'value' ) );

    }

    @IsTest
    static void test_getInvocableActions_EmailAlert() {

        String operation = 'getInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'EmailAlert',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Email Alert', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Email_Alert', resultAction.get( 'value' ) );

    }

    @IsTest
    static void test_getInvocableActions_Apex() {

        String operation = 'getInvocableActions';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'Apex',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Apex', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Apex', resultAction.get( 'value' ) );

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_getInvocableActionInputs_Workflow() {

        String operation = 'getInvocableActionInputs';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'Workflow',
            'actionName' => '',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Record ID', resultAction.get( 'label' ) );
        System.assertEquals( 'ContextId', resultAction.get( 'name' ) );

    }

    @IsTest
    static void test_getInvocableActionInputs_Flow() {

        String operation = 'getInvocableActionInputs';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'Flow',
            'actionName' => 'Test_Flow',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Input', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Input', resultAction.get( 'name' ) );

    }

    @IsTest
    static void test_getInvocableActionInputs_QuickAction() {

        String operation = 'getInvocableActionInputs';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'QuickAction',
            'actionName' => 'Test_Quick_Action',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Input', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Input', resultAction.get( 'name' ) );

    }

    @IsTest
    static void test_getInvocableActionInputs_EmailAlert() {

        String operation = 'getInvocableActionInputs';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'EmailAlert',
            'actionName' => 'Test_Email_Alert',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Input', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Input', resultAction.get( 'name' ) );

    }

    @IsTest
    static void test_getInvocableActionInputs_Apex() {

        String operation = 'getInvocableActionInputs';
        Map<String, Object> params = new Map<String, Object>{
            'actionType' => 'Apex',
            'actionName' => 'Test_Apex',
            'objectName' => 'Account'
        };

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( operation, params );

        Test.stopTest();

        List<Object> result = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, result.size() );

        Map<String, Object> resultAction = (Map<String, Object>) result[0];

        System.assertEquals( 'Test Input', resultAction.get( 'label' ) );
        System.assertEquals( 'Test_Input', resultAction.get( 'name' ) );

    }

    // --------------------------------------------------------------------------

    @IsTest( SeeAllData = true )
    static void test_get_reports() {

        // Reports and Report Folders cannot be created in unit tests as these are considered 'metadata'.
        // So we rely on the package bundling test folder/report and must use SeeAllData = true.

        Folder f = [ SELECT Id FROM Folder WHERE DeveloperName = 'Mass_Action_Test_Reports' AND NamespacePrefix = null ];
        Report r = [ SELECT Id FROM Report WHERE DeveloperName = 'MA_Test_Account_Report' AND NamespacePrefix = null ];

        Map<String, Object> responseBodyMap;

        Test.startTest();

        // ---

        responseBodyMap = test_handlePost( 'getReportFolders', new Map<String, Object>() );

        List<Object> reportFolders = (List<Object>) responseBodyMap.get( 'result' );

        Boolean folderFound = false;
        for ( Object item : reportFolders ) {
            Map<String, Object> reportFolder = (Map<String, Object>) item;
            folderFound = ( folderFound || ( String.valueOf( reportFolder.get( 'value' ) ).left( 15 ) == String.valueOf( f.Id ).left( 15 ) ) );
        }
        System.assertEquals( true, folderFound, 'should have found folder' );

        // ---

        responseBodyMap = test_handlePost( 'getReportsByFolder', new Map<String, Object>{
            'folderId' => f.Id
        });

        List<Object> reports = (List<Object>) responseBodyMap.get( 'result' );

        Boolean reportFound = false;
        for ( Object item : reports ) {
            Map<String, Object> rpt = (Map<String, Object>) item;
            reportFound = ( reportFound || ( String.valueOf( rpt.get( 'value' ) ).left( 15 ) == String.valueOf( r.Id ).left( 15 ) ) );
        }
        System.assertEquals( true, reportFound, 'should have found report' );

        // ---

        responseBodyMap = test_handlePost( 'getReport', new Map<String, Object>{
            'recordId' => r.Id
        });

        Map<String, Object> rpt = (Map<String, Object>) responseBodyMap.get( 'result' );

        System.assertEquals( r.Id, rpt.get( 'Id' ) );

        // ---

        responseBodyMap = test_handlePost( 'getReportColumns', new Map<String, Object>{
            'reportId' => r.Id
        });

        List<Object> reportColumns = (List<Object>) responseBodyMap.get( 'result' );

        Boolean columnFound = false;
        for ( Object item : reportColumns ) {
            Map<String, Object> reportColumn = (Map<String, Object>) item;
            columnFound = ( columnFound || reportColumn.get( 'value' ) == 'ACCOUNT_ID' );
        }
        System.assertEquals( true, columnFound, 'report should have account id column' );

        // --

        Test.stopTest();

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_getObjectNames() {

        Map<String, SObjectType> globalDescribeMap = Schema.getGlobalDescribe();

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getObjectNames', new Map<String, Object>() );

        Test.stopTest();

        List<Object> objectNames = (List<Object>) responseBodyMap.get( 'result' );

        // Schema.getGlobalDescribe() returns the objects that exist as of the API version
        // of the class that calls it. This test class is pinned to API 66.0 (see the
        // modification log) while MA_EditConfigRestController compiles at 67.0, so the
        // controller legitimately returns objects that 66.0 does not know about
        // (VoiceCallHistory, WorkItemEvent, and similar 67.0 additions). Asserting an
        // exact match would be asserting on the version gap, not on the controller.
        //
        // What the controller actually promises is that every object visible to it is
        // offered exactly once, so assert that every object this class can see came back.
        Set<String> returnedNames = new Set<String>();
        for ( Object item : objectNames ) {
            Map<String, Object> objectName = (Map<String, Object>) item;
            String value = String.valueOf( objectName.get( 'value' ) );
            System.assert( String.isNotBlank( value ), 'Every option must carry an object name.' );
            returnedNames.add( value );
        }

        System.assertEquals( objectNames.size(), returnedNames.size(), 'Object names should not be duplicated.' );

        for ( String objectName : globalDescribeMap.keySet() ) {
            String apiName = globalDescribeMap.get( objectName ).getDescribe().getName();
            System.assert(
                returnedNames.contains( apiName ),
                'Expected getObjectNames to include ' + apiName
            );
        }

    }

    @IsTest
    static void test_getObjectNamesWithListViews() {

        Set<String> sobjectsWithListViews = new Set<String>();
        for ( AggregateResult result : [
            SELECT SObjectType
            FROM ListView
            WHERE IsSoqlCompatible = true AND SObjectType != null
            GROUP BY SObjectType
            ORDER BY SObjectType ASC
            LIMIT 2000
        ]) {
            // lowercase the object names to match keys in the global describe map
            // because the Set method `contains` is case-sensitive
            sobjectsWithListViews.add( ( (String) result.get( 'SObjectType' ) ).toLowerCase() );
        }

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getObjectNamesWithListViews', new Map<String, Object>() );

        Test.stopTest();

        List<Object> objectNames = (List<Object>) responseBodyMap.get( 'result' );

        for ( Object item : objectNames ) {
            Map<String, Object> objectName = (Map<String, Object>) item;
            System.assert( sobjectsWithListViews.contains( String.valueOf( objectName.get( 'value' ) ).toLowerCase() ) );
        }

    }

    @IsTest
    static void test_getListViewsByObject() {

        String objectName = MA_NamespaceUtils.NAMESPACE_API + 'Mass_Action_Configuration__c';
        ListView lv = [ SELECT Id, Name, DeveloperName, SobjectType FROM ListView WHERE DeveloperName = 'All' AND SobjectType = :objectName AND IsSoqlCompatible = true LIMIT 1 ];

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getListViewsByObject', new Map<String, Object>{
            'objectName' => objectName
        });

        Test.stopTest();

        List<Object> listViews = (List<Object>) responseBodyMap.get( 'result' );

        Boolean found = false;
        for ( Object item : listViews ) {
            Map<String, Object> listView = (Map<String, Object>) item;
            found = ( found || String.valueOf( listView.get( 'label' ) ).equalsIgnoreCase( lv.Name ) );
        }

        System.assertEquals( true, found );

    }

    @IsTest
    static void test_getListViewById() {

        String objectName = MA_NamespaceUtils.NAMESPACE_API + 'Mass_Action_Configuration__c';
        ListView lv = [ SELECT Id, Name, DeveloperName, SobjectType FROM ListView WHERE DeveloperName = 'All' AND SobjectType = :objectName AND IsSoqlCompatible = true LIMIT 1 ];

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getListView', new Map<String, Object>{
            'recordId' => lv.Id
        });

        Test.stopTest();

        Map<String, Object> listView = (Map<String, Object>) responseBodyMap.get( 'result' );

        System.assertEquals( lv.Id, listView.get( 'Id' ), 'should find list view' );

    }

    @IsTest
    static void test_getListViewColumns() {

        String objectName = MA_NamespaceUtils.NAMESPACE_API + 'Mass_Action_Configuration__c';
        ListView lv = [ SELECT Id, Name, DeveloperName, SobjectType FROM ListView WHERE DeveloperName = 'All' AND SobjectType = :objectName AND IsSoqlCompatible = true LIMIT 1 ];

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getListViewColumns', new Map<String, Object>{
            'listViewId' => lv.Id
        });

        Test.stopTest();

        List<Object> listViewColumns = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 3, listViewColumns.size() );

        Boolean hasAccountIdColumn = false;
        Boolean hasAccountNameColumn = false;
        Boolean hasOwnerIdColumn = false;

        for ( Object item : listViewColumns ) {

            Map<String, Object> listViewColumn = (Map<String, Object>) item;

            switch on ( (String) listViewColumn.get( 'label' ) ) {
                when 'Account ID' {
                    System.assertEquals( 'Id', listViewColumn.get( 'value' ) );
                    System.assertEquals( 'ID', listViewColumn.get( 'dataType' ) );
                    hasAccountIdColumn = true;
                }
                when 'Account Name' {
                    System.assertEquals( 'Name', listViewColumn.get( 'value' ) );
                    System.assertEquals( 'STRING', listViewColumn.get( 'dataType' ) );
                    hasAccountNameColumn = true;
                }
                when 'Owner ID' {
                    System.assertEquals( 'Owner.Id', listViewColumn.get( 'value' ) );
                    System.assertEquals( 'ID', listViewColumn.get( 'dataType' ) );
                    hasOwnerIdColumn = true;
                }
            }

        }

        System.assert( hasAccountIdColumn, 'missing Account ID column' );
        System.assert( hasAccountNameColumn, 'missing Account Name column' );
        System.assert( hasOwnerIdColumn, 'missing Owner ID column' );

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_getSoqlQueryResults() {

        // we return mock results, the query doesn't matter
        // other than to provide the illusion of realism
        // because we execute the query via the REST API
        String query = 'SELECT Id, Name FROM Account LIMIT 1';

        Test.startTest();

        // Test Success (no next records url)

        Map<String, Object> responseBodyMap = test_handlePost( 'getSoqlQueryResults', new Map<String, Object>{
            'query' => query
        });

        Map<String, Object> result = (Map<String, Object>) responseBodyMap.get( 'result' );

        System.assertEquals( 1, (Integer) result.get( 'totalSize' ) );
        System.assertEquals( true, (Boolean) result.get( 'done' ) );
        System.assert( String.isBlank( (String) result.get( 'nextRecordsUrl' ) ) );

        List<Object> records = (List<Object>) result.get( 'records' );
        System.assertEquals( 1, records.size() );

        for ( Object item : records ) {
            Map<String, Object> row = (Map<String, Object>) item;
            System.assertEquals( '001f400000CukanAAB', row.get( Account.Id.getDescribe().getName() ) );
            System.assertEquals( 'Test Account 1', row.get( Account.Name.getDescribe().getName() ) );
        }

        // Test Success (yes next records url)

        responseBodyMap = test_handlePost( 'getSoqlQueryResults', new Map<String, Object>{
            'query' => query,
            'batchSize' => 500
        });

        result = (Map<String, Object>) responseBodyMap.get( 'result' );

        System.assertEquals( 501, (Integer) result.get( 'totalSize' ), 'should be 1 more than requested query options batch size' );
        System.assertEquals( false, (Boolean) result.get( 'done' ) );
        System.assert( String.isNotBlank( (String) result.get( 'nextRecordsUrl' ) ) );

        records = (List<Object>) result.get( 'records' );
        System.assertEquals( 1, records.size() );

        for ( Object item : records ) {
            Map<String, Object> row = (Map<String, Object>) item;
            System.assertEquals( '001f400000CukanAAB', row.get( Account.Id.getDescribe().getName() ) );
            System.assertEquals( 'Test Account 1', row.get( Account.Name.getDescribe().getName() ) );
        }

        // Test Error

        try {

            responseBodyMap = test_handlePost( 'getSoqlQueryResults', new Map<String, Object>{
                'query' => 'TEST_FAIL'
            });

            System.assertEquals( false, responseBodyMap.get( 'success' ), 'should fail' );
            System.assert( ( (String) responseBodyMap.get( 'error' ) ).startsWithIgnoreCase( 'SOQL Query Error:' ), 'failed for wrong reason' );

        } catch ( Exception e ) {

            System.debug( LoggingLevel.ERROR, e.getMessage() + ' : ' + e.getStackTraceString() );
            System.assert( false, 'failed for wrong reason: ' + e.getMessage() );

        }

        Test.stopTest();

    }

    @IsTest
    static void test_getSoqlQueryNextRecordsResults() {

        Test.startTest();

        // Test Success

        Integer queryOptionsBatchSize = 500;

        Map<String, Object> responseBodyMap = test_handlePost( 'getSoqlQueryNextRecordsResults', new Map<String, Object>{
            'nextRecordsId' => '01gf400001MMCpeAAH-' + queryOptionsBatchSize
        });

        Map<String, Object> result = (Map<String, Object>) responseBodyMap.get( 'result' );

        System.assertEquals( queryOptionsBatchSize + 1, (Integer) result.get( 'totalSize' ), 'should be one more than query options batch size' );
        System.assertEquals( true, (Boolean) result.get( 'done' ) );
        System.assert( String.isBlank( (String) result.get( 'nextRecordsUrl' ) ) );

        List<Object> records = (List<Object>) result.get( 'records' );
        System.assertEquals( 1, records.size() );

        for ( Object item : records ) {
            Map<String, Object> row = (Map<String, Object>) item;
            System.assertEquals( '001f400000lxT2JAAU', row.get( Account.Id.getDescribe().getName() ) );
            System.assertEquals( 'Test Account 2', row.get( Account.Name.getDescribe().getName() ) );
        }

        // Test Error

        try {

            responseBodyMap = test_handlePost( 'getSoqlQueryNextRecordsResults', new Map<String, Object>{
                'nextRecordsId' => 'TEST_FAIL'
            });

            System.assertEquals( false, responseBodyMap.get( 'success' ), 'should fail' );
            System.assert( ( (String) responseBodyMap.get( 'error' ) ).startsWithIgnoreCase( 'SOQL Query Error:' ), 'failed for wrong reason' );

        } catch ( Exception e ) {

            System.debug( LoggingLevel.ERROR, e.getMessage() + ' : ' + e.getStackTraceString() );
            System.assert( false, 'failed for wrong reason: ' + e.getMessage() );

        }

        Test.stopTest();

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_getNamedCredentials() {

        String namedCredential = 'Mass_Action_Test_Named_Credential';

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getNamedCredentials', new Map<String, Object>() );

        Test.stopTest();

        List<Object> namedCredentials = (List<Object>) responseBodyMap.get( 'result' );
        System.assertEquals( 1, namedCredentials.size() );

        for ( Object item : namedCredentials ) {
            Map<String, Object> credential = (Map<String, Object>) item;
            System.assertEquals( namedCredential, credential.get( 'value' ) );
        }

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_getConfiguration() {

        Mass_Action_Configuration__c config = new Mass_Action_Configuration__c(
            Name = 'Test Config',
            DeveloperName__c = 'Test_Config',
            Active__c = false,
            Batch_Size__c = 200,
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Source_Type__c = 'ListView',
            Source_List_View_ID__c = '00Bf40000017w5h',
            Target_Type__c = 'Flow',
            Target_Action_Name__c = 'Test_Flow',
            Schedule_Frequency__c = 'Custom',
            Schedule_Cron__c = '0 0 1 * * ?'
        );

        insert config;

        Mass_Action_Mapping__c fieldMapping = new Mass_Action_Mapping__c(
            Mass_Action_Configuration__c = config.Id,
            Source_Field_Name__c = 'SourceField',
            Target_Field_Name__c = 'TargetField'
        );

        insert fieldMapping;

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getConfiguration', new Map<String, Object>{
            'recordId' => config.Id
        });

        Object result = responseBodyMap.get( 'result' );

        MA_MassActionConfigWrapper wrapper = (MA_MassActionConfigWrapper) JSON.deserialize( JSON.serialize( result ), MA_MassActionConfigWrapper.class );

        System.assertEquals( config.Id, wrapper.recordId );
        System.assertEquals( config.Name, wrapper.name );
        System.assertEquals( config.DeveloperName__c, wrapper.developerName );
        System.assertEquals( config.Description__c, wrapper.description );
        System.assertEquals( config.Active__c, wrapper.active );
        System.assertEquals( config.Batch_Size__c, wrapper.batchSize );
        System.assertEquals( config.Named_Credential__c, wrapper.namedCredential );
        System.assertEquals( config.Source_Type__c, wrapper.sourceType );
        System.assertEquals( config.Source_List_View_ID__c, wrapper.sourceListViewID );
        System.assertEquals( config.Source_Report_ID__c, wrapper.sourceReportID );
        System.assertEquals( config.Source_Report_Column_Name__c, wrapper.sourceReportColumnName );
        System.assertEquals( config.Target_Type__c, wrapper.targetType );
        System.assertEquals( config.Target_SObject_Type__c, wrapper.targetSobjectType );
        System.assertEquals( config.Target_Action_Name__c, wrapper.targetActionName );
        System.assertEquals( config.Target_Apex_Script__c, wrapper.targetApexScript );
        System.assertEquals( config.Schedule_Frequency__c, wrapper.scheduleFrequency );
        System.assertEquals( config.Schedule_Cron__c, wrapper.scheduleCron );
        System.assertEquals( config.Schedule_SecondOfMinute__c, wrapper.scheduleSecondOfMinute );
        System.assertEquals( config.Schedule_MinuteOfHour__c, wrapper.scheduleMinuteOfHour );
        System.assertEquals( config.Schedule_HourOfDay__c, wrapper.scheduleHourOfDay );
        System.assertEquals( config.Schedule_DayOfMonth__c, wrapper.scheduleDayOfMonth );
        System.assertEquals( config.Schedule_MonthOfYear__c, wrapper.scheduleMonthOfYear );
        System.assertEquals( config.Schedule_DayOfWeek__c, wrapper.scheduleDayOfWeek );

        System.assertEquals( 1, wrapper.fieldMappings.size() );
        System.assertEquals( fieldMapping.Source_Field_Name__c, wrapper.fieldMappings[0].sourceFieldName );
        System.assertEquals( fieldMapping.Target_Field_Name__c, wrapper.fieldMappings[0].targetFieldName );

        Mass_Action_Configuration__c config2 = wrapper.toConfiguration();

        System.assertEquals( config.Id, config2.Id );
        System.assertEquals( config.Name, config2.Name );
        System.assertEquals( config.DeveloperName__c, config2.DeveloperName__c );
        System.assertEquals( config.Description__c, config2.Description__c );
        System.assertEquals( config.Active__c, config2.Active__c );
        System.assertEquals( config.Batch_Size__c, config2.Batch_Size__c );
        System.assertEquals( config.Named_Credential__c, config2.Named_Credential__c );
        System.assertEquals( config.Source_Type__c, config2.Source_Type__c );
        System.assertEquals( config.Source_List_View_ID__c, config2.Source_List_View_ID__c );
        System.assertEquals( config.Source_Report_ID__c, config2.Source_Report_ID__c );
        System.assertEquals( config.Source_Report_Column_Name__c, config2.Source_Report_Column_Name__c );
        System.assertEquals( config.Target_Type__c, config2.Target_Type__c );
        System.assertEquals( config.Target_SObject_Type__c, config2.Target_SObject_Type__c );
        System.assertEquals( config.Target_Action_Name__c, config2.Target_Action_Name__c );
        System.assertEquals( config.Target_Apex_Script__c, config2.Target_Apex_Script__c );
        System.assertEquals( config.Schedule_Frequency__c, config2.Schedule_Frequency__c );
        System.assertEquals( config.Schedule_Cron__c, config2.Schedule_Cron__c );
        System.assertEquals( config.Schedule_SecondOfMinute__c, config2.Schedule_SecondOfMinute__c );
        System.assertEquals( config.Schedule_MinuteOfHour__c, config2.Schedule_MinuteOfHour__c );
        System.assertEquals( config.Schedule_HourOfDay__c, config2.Schedule_HourOfDay__c );
        System.assertEquals( config.Schedule_DayOfMonth__c, config2.Schedule_DayOfMonth__c );
        System.assertEquals( config.Schedule_MonthOfYear__c, config2.Schedule_MonthOfYear__c );
        System.assertEquals( config.Schedule_DayOfWeek__c, config2.Schedule_DayOfWeek__c );

        Test.stopTest();

    }

    @IsTest
    static void test_getConfigurationObjectDescribe() {

        String objectName = MA_NamespaceUtils.NAMESPACE_API + 'Mass_Action_Configuration__c';
        DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get( objectName ).getDescribe();
        Map<String, SObjectField> fieldsMap = objectDescribe.fields.getMap();

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'getConfigurationObjectDescribe', new Map<String, Object>() );

        Test.stopTest();

        Map<String, Object> configDesc = (Map<String, Object>) responseBodyMap.get( 'result' );

        System.assertEquals( objectDescribe.getName(), configDesc.get( 'name' ) );
        System.assertEquals( objectDescribe.getLocalName(), configDesc.get( 'localName' ) );
        System.assertEquals( objectDescribe.getLabel(), configDesc.get( 'label' ) );
        System.assertEquals( objectDescribe.getLabelPlural(), configDesc.get( 'labelPlural' ) );

        Map<String, Object> configFieldsDesc = (Map<String, Object>) configDesc.get( 'fields' );

        for ( String fieldLocalName : configFieldsDesc.keySet() ) {

            Map<String, Object> configFieldDesc = (Map<String, Object>) configFieldsDesc.get( fieldLocalName );
            DescribeFieldResult fieldDesc = fieldsMap.get( String.valueOf( configFieldDesc.get( 'name' ) ) ).getDescribe();

            System.assertEquals( fieldDesc.getName(), configFieldDesc.get( 'name' ) );
            System.assertEquals( fieldDesc.getLocalName(), configFieldDesc.get( 'localName' ) );
            System.assertEquals( fieldDesc.getLabel(), configFieldDesc.get( 'label' ) );
            System.assertEquals( fieldDesc.getInlineHelpText(), configFieldDesc.get( 'helpText' ) );

        }

    }

    @IsTest
    static void test_saveConfiguration() {

        MA_MassActionConfigWrapper wrapper = new MA_MassActionConfigWrapper();
        wrapper.name = 'Test Config';
        wrapper.developerName = 'Test_Config';
        wrapper.active = false;
        wrapper.batchSize = 200;
        wrapper.namedCredential = 'Mass_Action_Test_Named_Credential';
        wrapper.sourceType = 'ListView';
        wrapper.sourceListViewID = '00Bf40000017w5h';
        wrapper.targetType = 'Flow';
        wrapper.targetActionName = 'Test_Flow';
        wrapper.scheduleFrequency = 'Custom';
        wrapper.scheduleCron = '0 0 1 * * ?';

        Map<String, String> fieldMappings = new Map<String, String>{
            'TargetField' => 'SourceField'
        };

        Test.startTest();

        // Test Success

        Map<String, Object> responseBodyMap = test_handlePost( 'saveConfiguration', new Map<String, Object>{
            'wrapperJson' => wrapper,
            'fieldMappingsJson' => fieldMappings
        });

        Map<String, Object> result = (Map<String, Object>) responseBodyMap.get( 'result' );

        System.assertEquals( true, responseBodyMap.get( 'success' ) );

        Mass_Action_Configuration__c config = MA_MassActionUtils.getConfiguration( (ID) result.get( 'recordId' ) );

        System.assertEquals( wrapper.name, config.Name );
        System.assertEquals( wrapper.active, config.Active__c );
        System.assertEquals( wrapper.batchSize, config.Batch_Size__c );
        System.assertEquals( wrapper.namedCredential, config.Named_Credential__c );
        System.assertEquals( wrapper.sourceType, config.Source_Type__c );
        System.assertEquals( wrapper.sourceListViewID, config.Source_List_View_ID__c );
        System.assertEquals( wrapper.targetType, config.Target_Type__c );
        System.assertEquals( wrapper.targetActionName, config.Target_Action_Name__c );
        System.assertEquals( wrapper.scheduleFrequency, config.Schedule_Frequency__c );
        System.assertEquals( wrapper.scheduleCron, config.Schedule_Cron__c );

        System.assertEquals( 1, config.Mass_Action_Mappings__r.size() );
        System.assertEquals( 'TargetField', config.Mass_Action_Mappings__r[0].Target_Field_Name__c );
        System.assertEquals( 'SourceField', config.Mass_Action_Mappings__r[0].Source_Field_Name__c );

        // Test Error

        try {

            responseBodyMap = test_handlePost( 'saveConfiguration', new Map<String, Object>() );

            System.assertEquals( false, responseBodyMap.get( 'success' ), 'should fail' );

        } catch ( Exception e ) {

            System.debug( LoggingLevel.ERROR, e.getMessage() + ' : ' + e.getStackTraceString() );
            System.assert( false, 'failed for wrong reason: ' + e.getMessage() );

        }

        Test.stopTest();

    }

    // --------------------------------------------------------------------------
    // Static (hard-coded) field mappings
    // --------------------------------------------------------------------------

    /**
     * A static value mapping assigns its literal with no source field involved, so the
     * source row does not need to contain anything for that target field and no
     * NoSourceFieldException is raised.
     */
    @IsTest
    static void test_build_action_inputs_static_value_mapping() {

        List<Mass_Action_Mapping__c> mappings = new List<Mass_Action_Mapping__c>{
            new Mass_Action_Mapping__c(
                Mapping_Type__c = 'Static Value',
                Source_Field_Name__c = null,
                Source_Value__c = 'HARD CODED',
                Target_Field_Name__c = 'StaticInput'
            )
        };

        // deliberately contains nothing that corresponds to the target field
        List<Map<String, Object>> sourceRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '001000000000001' }
        };

        Test.startTest();

        List<Map<String, Object>> targetRows = MA_MassActionUtils.buildActionInputs( sourceRows, mappings );

        Test.stopTest();

        System.assertEquals( 1, targetRows.size() );
        System.assertEquals( 1, targetRows[0].size(), 'only the static mapping should produce a key' );
        System.assertEquals( true, targetRows[0].containsKey( 'StaticInput' ) );
        System.assertEquals( 'HARD CODED', targetRows[0].get( 'StaticInput' ) );

    }

    /**
     * A configuration may mix both kinds of mapping. The source field mapping still reads
     * from the source row and the static mapping still contributes its literal.
     */
    @IsTest
    static void test_build_action_inputs_mixed_mappings() {

        List<Mass_Action_Mapping__c> mappings = new List<Mass_Action_Mapping__c>{
            new Mass_Action_Mapping__c(
                Mapping_Type__c = 'Source Field',
                Source_Field_Name__c = 'Id',
                Source_Value__c = null,
                Target_Field_Name__c = 'ContextId'
            ),
            new Mass_Action_Mapping__c(
                Mapping_Type__c = 'Static Value',
                Source_Field_Name__c = null,
                Source_Value__c = 'Nightly Batch',
                Target_Field_Name__c = 'RunLabel'
            )
        };

        List<Map<String, Object>> sourceRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '001000000000001' },
            new Map<String, Object>{ 'Id' => '001000000000002' }
        };

        Test.startTest();

        List<Map<String, Object>> targetRows = MA_MassActionUtils.buildActionInputs( sourceRows, mappings );

        Test.stopTest();

        System.assertEquals( 2, targetRows.size() );

        System.assertEquals( 2, targetRows[0].size() );
        System.assertEquals( '001000000000001', targetRows[0].get( 'ContextId' ) );
        System.assertEquals( 'Nightly Batch', targetRows[0].get( 'RunLabel' ) );

        // the static literal is repeated for every row, the source value varies
        System.assertEquals( '001000000000002', targetRows[1].get( 'ContextId' ) );
        System.assertEquals( 'Nightly Batch', targetRows[1].get( 'RunLabel' ) );

    }

    /**
     * Mappings created before Mapping_Type__c existed have it blank. They must keep
     * behaving as source field mappings, including raising NoSourceFieldException when the
     * source row has no such field.
     */
    @IsTest
    static void test_build_action_inputs_blank_mapping_type_is_source_field() {

        List<Mass_Action_Mapping__c> mappings = new List<Mass_Action_Mapping__c>{
            new Mass_Action_Mapping__c(
                Mapping_Type__c = null,
                Source_Field_Name__c = 'Id',
                Target_Field_Name__c = 'ContextId'
            )
        };

        Test.startTest();

        // present in the source row, behaves as before
        List<Map<String, Object>> targetRows = MA_MassActionUtils.buildActionInputs(
            new List<Map<String, Object>>{ new Map<String, Object>{ 'Id' => '001000000000001' } },
            mappings
        );

        System.assertEquals( '001000000000001', targetRows[0].get( 'ContextId' ) );

        // absent from the source row, still raises
        Boolean thrown = false;

        try {
            MA_MassActionUtils.buildActionInputs(
                new List<Map<String, Object>>{ new Map<String, Object>{ 'SomeOtherField' => 'x' } },
                mappings
            );
        } catch ( MA_Exceptions.NoSourceFieldException e ) {
            thrown = true;
        }

        Test.stopTest();

        System.assertEquals( true, thrown, 'a legacy mapping with a missing source field should still raise' );

    }

    /**
     * Source_Field_Name__c is no longer required at the field level, so a source field
     * mapping saved with it blank must raise rather than throw a NullPointerException.
     */
    @IsTest
    static void test_build_action_inputs_blank_source_field_name_raises() {

        List<Mass_Action_Mapping__c> mappings = new List<Mass_Action_Mapping__c>{
            new Mass_Action_Mapping__c(
                Mapping_Type__c = 'Source Field',
                Source_Field_Name__c = null,
                Target_Field_Name__c = 'ContextId'
            )
        };

        Boolean thrown = false;

        Test.startTest();

        try {
            MA_MassActionUtils.buildActionInputs(
                new List<Map<String, Object>>{ new Map<String, Object>{ 'Id' => '001000000000001' } },
                mappings
            );
        } catch ( MA_Exceptions.NoSourceFieldException e ) {
            thrown = true;
        }

        Test.stopTest();

        System.assertEquals( true, thrown, 'expected NoSourceFieldException, not a NullPointerException' );

    }

    /**
     * The save payload accepts both the legacy string shape and the extended object shape,
     * so a configuration mixing both persists the right Mass_Action_Mapping__c records.
     */
    @IsTest
    static void test_save_configuration_with_static_value_mapping() {

        MA_MassActionConfigWrapper wrapper = new MA_MassActionConfigWrapper();
        wrapper.name = 'Test Config Static';
        wrapper.developerName = 'Test_Config_Static';
        wrapper.active = false;
        wrapper.batchSize = 200;
        wrapper.sourceType = 'SOQL';
        wrapper.sourceSoqlQuery = 'SELECT Id FROM Account';
        wrapper.targetType = 'Flow';
        wrapper.targetActionName = 'Test_Flow';
        wrapper.scheduleFrequency = 'Custom';
        wrapper.scheduleCron = '0 0 1 * * ?';

        // legacy string shape alongside the extended object shape
        Map<String, Object> fieldMappings = new Map<String, Object>{
            'ContextId' => 'Id',
            'RunLabel' => new Map<String, Object>{
                'mappingType' => 'Static Value',
                'sourceFieldName' => null,
                'sourceValue' => 'Nightly Batch'
            },
            // a static mapping with no literal is skipped, mirroring how an unmapped
            // optional source field is skipped
            'IgnoredInput' => new Map<String, Object>{
                'mappingType' => 'Static Value',
                'sourceFieldName' => null,
                'sourceValue' => ''
            }
        };

        Test.startTest();

        Map<String, Object> result = MA_MassActionUtils.saveConfiguration(
            JSON.serialize( wrapper ),
            JSON.serialize( fieldMappings )
        );

        Test.stopTest();

        System.assertEquals( true, result.get( 'success' ) );

        Mass_Action_Configuration__c config = MA_MassActionUtils.getConfiguration( (ID) result.get( 'recordId' ) );

        Map<String, Mass_Action_Mapping__c> mappingsByTarget = new Map<String, Mass_Action_Mapping__c>();
        for ( Mass_Action_Mapping__c mapping : config.Mass_Action_Mappings__r ) {
            mappingsByTarget.put( mapping.Target_Field_Name__c, mapping );
        }

        System.assertEquals( 2, mappingsByTarget.size(), 'the blank static value should not have been saved' );

        Mass_Action_Mapping__c sourceFieldMapping = mappingsByTarget.get( 'ContextId' );
        System.assertEquals( 'Source Field', sourceFieldMapping.Mapping_Type__c );
        System.assertEquals( 'Id', sourceFieldMapping.Source_Field_Name__c );
        System.assertEquals( null, sourceFieldMapping.Source_Value__c );

        Mass_Action_Mapping__c staticMapping = mappingsByTarget.get( 'RunLabel' );
        System.assertEquals( 'Static Value', staticMapping.Mapping_Type__c );
        System.assertEquals( null, staticMapping.Source_Field_Name__c );
        System.assertEquals( 'Nightly Batch', staticMapping.Source_Value__c );

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_getCalloutRestEndpointURL() {

        Test.startTest();

        System.assertEquals( 'callout:TestNamedCredential' + MA_MassActionUtils.REST_API_PATH, MA_MassActionUtils.getCalloutRestEndpointURL( 'TestNamedCredential' ) );
        System.assertEquals( MA_MassActionUtils.REST_API_SERVICES_URL, MA_MassActionUtils.getCalloutRestEndpointURL( null ) );
        System.assertEquals( MA_MassActionUtils.REST_API_SERVICES_URL, MA_MassActionUtils.getCalloutRestEndpointURL( '' ) );
        System.assertEquals( MA_MassActionUtils.REST_API_SERVICES_URL, MA_MassActionUtils.getCalloutRestEndpointURL( ' ' ) );

        Test.stopTest();

    }

    @IsTest
    static void test_getCalloutSoapEndpointURL() {

        Test.startTest();

        System.assertEquals( 'callout:TestNamedCredential' + MA_MassActionUtils.SOAP_API_PATH, MA_MassActionUtils.getCalloutSoapEndpointURL( 'TestNamedCredential' ) );
        System.assertEquals( MA_MassActionUtils.SOAP_API_SERVICES_URL, MA_MassActionUtils.getCalloutSoapEndpointURL( null ) );
        System.assertEquals( MA_MassActionUtils.SOAP_API_SERVICES_URL, MA_MassActionUtils.getCalloutSoapEndpointURL( '' ) );
        System.assertEquals( MA_MassActionUtils.SOAP_API_SERVICES_URL, MA_MassActionUtils.getCalloutSoapEndpointURL( ' ' ) );

        Test.stopTest();

    }

    // --------------------------------------------------------------------------

    @IsTest
    static void test_unsupported_operation() {

        Test.setMock( HttpCalloutMock.class, new MA_HttpCalloutMock() );

        Test.startTest();

        Map<String, Object> responseBodyMap = test_handlePost( 'FAKE_OPERATION', new Map<String, Object>() );

        Test.stopTest();

        System.assertEquals( false, responseBodyMap.get( 'success' ), 'should fail' );

    }

    @IsTest
    static void test_calloutMock_noMatchingURL() {

        Test.setMock( HttpCalloutMock.class, new MA_HttpCalloutMock() );

        Test.startTest();

        // Test GET

        HttpRequest getReq = new HttpRequest();
        getReq.setMethod( 'GET' );
        getReq.setEndpoint( 'nowhere' );

        HttpResponse getRes = new Http().send( getReq );
        System.assertEquals( 'ERROR', getRes.getStatus() );
        System.assertEquals( 400, getRes.getStatusCode() );
        System.assert( getRes.getBody().startsWithIgnoreCase( 'Unsupported endpoint' ) );

        // Test POST

        HttpRequest postReq = new HttpRequest();
        postReq.setMethod( 'POST' );
        postReq.setEndpoint( 'nowhere' );

        HttpResponse postRes = new Http().send( postReq );
        System.assertEquals( 'ERROR', postRes.getStatus() );
        System.assertEquals( 400, postRes.getStatusCode() );
        System.assert( postRes.getBody().startsWithIgnoreCase( 'Unsupported endpoint' ) );

        Test.stopTest();

    }

    // --------------------------------------------------------------------------

    static Map<String, Object> test_handlePost( String operation, Map<String, Object> params ) {

        Test.setMock( HttpCalloutMock.class, new MA_HttpCalloutMock() );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        req.httpMethod = 'POST';
        req.requestURI = '/config/edit/';
        req.addParameter( 'operation', operation );
        req.requestBody = Blob.valueOf( JSON.serializePretty( params ) );
        req.addHeader( 'Origin', 'https://testdomain.my.salesforce.com' );
        req.addHeader( 'Content-Type', 'application/json; charset=utf-8' );
        req.addHeader( 'Accepts', 'application/json' );

        MA_EditConfigRestController.handlePost();

        System.debug( res );
        System.debug( res.responseBody.toString() );

        Map<String, Object> responseBodyMap = (Map<String, Object>) JSON.deserializeUntyped( res.responseBody.toString() );

        return responseBodyMap;
    }

}
/*
BSD 3-Clause License

Copyright (c) 2017-2023, Doug Ayers, douglascayers.com
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/