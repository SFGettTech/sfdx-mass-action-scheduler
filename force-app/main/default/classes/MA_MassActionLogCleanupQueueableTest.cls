/**
 * Author:       Josh Gettman
 * Date:         2026-10-13
 * Description:  Tests for MA_MassActionLogCleanupQueueable.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-10-13 | Josh Gettman | Initial build
 * ---------------------------------------------------------------------------
 */
@IsTest
private class MA_MassActionLogCleanupQueueableTest {

    @IsTest
    static void test_deletes_orphan_child_logs_only() {

        Map<String,RecordTypeInfo> logRecordTypeInfosMap = Mass_Action_Log__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();

        Mass_Action_Configuration__c config = new Mass_Action_Configuration__c(
            Name = 'Test Config',
            DeveloperName__c = 'Test_Config'
        );

        insert config;

        Mass_Action_Log__c parentLog = new Mass_Action_Log__c(
            RecordTypeId = logRecordTypeInfosMap.get( 'Parent_Log' ).getRecordTypeId(),
            Mass_Action_Configuration__c = config.Id
        );

        insert parentLog;

        List<Mass_Action_Log__c> childLogs = new List<Mass_Action_Log__c>();

        for ( Integer i = 0; i < 20; i++ ) {
            childLogs.add( new Mass_Action_Log__c(
                RecordTypeId = logRecordTypeInfosMap.get( 'Child_Log' ).getRecordTypeId(),
                Mass_Action_Configuration__c = config.Id,
                // half orphaned, half still attached to a live parent
                Parent_Log__c = ( Math.mod( i, 2 ) == 0 ? null : parentLog.Id )
            ));
        }

        insert childLogs;

        Test.startTest();

        MA_MassActionLogCleanupQueueable.enqueue();
        MA_MassActionLogCleanupQueueable.enqueue(); // second call is a no-op

        System.assertEquals( 1, Limits.getQueueableJobs() );

        Test.stopTest();

        System.assertEquals( 0, [ SELECT COUNT() FROM Mass_Action_Log__c WHERE RecordType.DeveloperName = 'Child_Log' AND Parent_Log__c = null ] );
        System.assertEquals( 10, [ SELECT COUNT() FROM Mass_Action_Log__c WHERE RecordType.DeveloperName = 'Child_Log' AND Parent_Log__c = :parentLog.Id ] );
        System.assertEquals( 1, [ SELECT COUNT() FROM Mass_Action_Log__c WHERE Id = :parentLog.Id ] );

    }

}