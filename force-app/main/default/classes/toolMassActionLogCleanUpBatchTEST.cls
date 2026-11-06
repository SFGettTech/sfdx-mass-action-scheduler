/*
 * Author:      Josh Gettman
 * Date:        2026-11-04
 * Description: Test class for toolMassActionLogCleanUpBatch. Covers child phase, parent phase
 *              (including parents kept because of newer child logs), delete-failure aggregation,
 *              recycle bin purge, input validation, run() entry point and scheduling.
 * Version:     1.0
 *
 * Modification Log:
 * Ver | Date       | Author       | Modification
 * 1.0 | 2026-11-04 | Josh Gettman | Initial build
 */
@IsTest
private class toolMassActionLogCleanUpBatchTEST {

    private static final String KEPT_PARENT = 'KEPT_PARENT';
    private static final String NEW_CHILD = 'NEW_CHILD';
    private static final String NEW_CHILD_OF_OLD_PARENT = 'NEW_CHILD_OF_OLD_PARENT';
    private static final String NEW_PARENT = 'NEW_PARENT';
    private static final String OLD_CHILD = 'OLD_CHILD';
    private static final String OLD_PARENT = 'OLD_PARENT';

    @TestSetup
    static void setupData() {
        Mass_Action_Configuration__c testConfig = new Mass_Action_Configuration__c(
            Active__c = false,
            DeveloperName__c = 'toolLogCleanUpTestConfig',
            Name = 'Log Clean Up Test Config'
        );
        insert testConfig;

        Mass_Action_Log__c oldParent = new Mass_Action_Log__c(Mass_Action_Configuration__c = testConfig.Id, Message__c = OLD_PARENT);
        Mass_Action_Log__c keptParent = new Mass_Action_Log__c(Mass_Action_Configuration__c = testConfig.Id, Message__c = KEPT_PARENT);
        Mass_Action_Log__c newParent = new Mass_Action_Log__c(Mass_Action_Configuration__c = testConfig.Id, Message__c = NEW_PARENT);
        insert new List<Mass_Action_Log__c>{ oldParent, keptParent, newParent };

        Mass_Action_Log__c oldChild = new Mass_Action_Log__c(Mass_Action_Configuration__c = testConfig.Id, Message__c = OLD_CHILD, Parent_Log__c = oldParent.Id);
        Mass_Action_Log__c newChildOfOldParent = new Mass_Action_Log__c(Mass_Action_Configuration__c = testConfig.Id, Message__c = NEW_CHILD_OF_OLD_PARENT, Parent_Log__c = keptParent.Id);
        Mass_Action_Log__c newChild = new Mass_Action_Log__c(Mass_Action_Configuration__c = testConfig.Id, Message__c = NEW_CHILD, Parent_Log__c = newParent.Id);
        insert new List<Mass_Action_Log__c>{ oldChild, newChildOfOldParent, newChild };

        Datetime oldDate = System.now().addDays(-60);
        Test.setCreatedDate(oldParent.Id, oldDate);
        Test.setCreatedDate(keptParent.Id, oldDate);
        Test.setCreatedDate(oldChild.Id, oldDate);
    }

    @IsTest
    static void childPhaseDeletesOnlyOldChildLogs() {
        Test.startTest();
        toolMassActionLogCleanUpBatch.run(30);
        Test.stopTest();

        Map<String, Mass_Action_Log__c> remainingLogs = getRemainingLogs();
        Assert.isFalse(remainingLogs.containsKey(OLD_CHILD), 'Old child log should be deleted in the child phase. Remaining: ' + remainingLogs.keySet());
        Assert.isTrue(remainingLogs.containsKey(NEW_CHILD), 'New child log should be kept. Remaining: ' + remainingLogs.keySet());
        Assert.isTrue(remainingLogs.containsKey(NEW_CHILD_OF_OLD_PARENT), 'New child of old parent should be kept. Remaining: ' + remainingLogs.keySet());
        Assert.isTrue(remainingLogs.containsKey(OLD_PARENT), 'Parents are not deleted until the parent phase. Remaining: ' + remainingLogs.keySet());
    }

    @IsTest
    static void parentPhaseKeepsParentsWithNewerChildren() {
        // Simulate a completed child phase
        delete [SELECT Id FROM Mass_Action_Log__c WHERE Message__c = :OLD_CHILD];

        Test.startTest();
        Database.executeBatch(new toolMassActionLogCleanUpBatch(30, false, 200, toolMassActionLogCleanUpBatch.PHASE_PARENT), 200);
        Test.stopTest();

        Map<String, Mass_Action_Log__c> remainingLogs = getRemainingLogs();
        Assert.isFalse(remainingLogs.containsKey(OLD_PARENT), 'Old parent with no children should be deleted. Remaining: ' + remainingLogs.keySet());
        Assert.isTrue(remainingLogs.containsKey(KEPT_PARENT), 'Old parent with a newer child should be kept. Remaining: ' + remainingLogs.keySet());
        Assert.isTrue(remainingLogs.containsKey(NEW_PARENT), 'New parent should be kept. Remaining: ' + remainingLogs.keySet());
        Assert.isTrue(remainingLogs.containsKey(NEW_CHILD_OF_OLD_PARENT), 'Child of kept parent should be untouched. Remaining: ' + remainingLogs.keySet());
    }

    @IsTest
    static void parentPhaseCountsSkippedParents() {
        delete [SELECT Id FROM Mass_Action_Log__c WHERE Message__c = :OLD_CHILD];
        List<SObject> parentScope = [SELECT Id FROM Mass_Action_Log__c WHERE Message__c IN (:OLD_PARENT, :KEPT_PARENT)];

        toolMassActionLogCleanUpBatch parentJob = new toolMassActionLogCleanUpBatch(30, false, 200, toolMassActionLogCleanUpBatch.PHASE_PARENT);
        Test.startTest();
        parentJob.execute((Database.BatchableContext) null, parentScope);
        parentJob.finish(null);
        Test.stopTest();

        Assert.areEqual(1, parentJob.deletedCount, 'Only the parent without children should be deleted. Summary: ' + parentJob.buildSummary(''));
        Assert.areEqual(1, parentJob.skippedParentCount, 'Parent with a newer child should be skipped. Summary: ' + parentJob.buildSummary(''));
        Assert.areEqual(0, parentJob.failedCount, 'No failures expected. Summary: ' + parentJob.buildSummary(''));
    }

    @IsTest
    static void deleteFailuresAreAggregated() {
        Mass_Action_Log__c oldChild = [SELECT Id FROM Mass_Action_Log__c WHERE Message__c = :OLD_CHILD LIMIT 1];
        delete oldChild;

        toolMassActionLogCleanUpBatch childJob = new toolMassActionLogCleanUpBatch(30);
        Test.startTest();
        childJob.execute((Database.BatchableContext) null, new List<SObject>{ oldChild });
        childJob.finish(null);
        Test.stopTest();

        Assert.areEqual(1, childJob.failedCount, 'Deleting an already-deleted log should be recorded as a failure. Summary: ' + childJob.buildSummary(''));
        Assert.isFalse(childJob.errorMessages.isEmpty(), 'Failure details should be captured. Summary: ' + childJob.buildSummary(''));
        Assert.isTrue(childJob.buildSummary('').contains('Errors:'), 'Summary should include the error section. Summary: ' + childJob.buildSummary(''));
    }

    @IsTest
    static void emptyRecycleBinPathRuns() {
        List<SObject> childScope = [SELECT Id FROM Mass_Action_Log__c WHERE Message__c = :OLD_CHILD];

        toolMassActionLogCleanUpBatch childJob = new toolMassActionLogCleanUpBatch(30, true, 200);
        Test.startTest();
        childJob.execute((Database.BatchableContext) null, childScope);
        Test.stopTest();

        Assert.areEqual(1, childJob.deletedCount, 'Old child should be deleted. Summary: ' + childJob.buildSummary(''));
        Assert.areEqual(0, childJob.failedCount, 'Recycle bin purge should not fail. Summary: ' + childJob.buildSummary(''));
    }

    @IsTest
    static void emptyScopeIsIgnored() {
        toolMassActionLogCleanUpBatch childJob = new toolMassActionLogCleanUpBatch(30);
        Test.startTest();
        childJob.execute((Database.BatchableContext) null, new List<SObject>());
        Test.stopTest();

        Assert.areEqual(0, childJob.deletedCount, 'Empty scope should delete nothing. Summary: ' + childJob.buildSummary(''));
    }

    @IsTest
    static void invalidInputsThrow() {
        assertThrows(null, 200, toolMassActionLogCleanUpBatch.PHASE_CHILD, 'null daysToKeep');
        assertThrows(-1, 200, toolMassActionLogCleanUpBatch.PHASE_CHILD, 'negative daysToKeep');
        assertThrows(30, 0, toolMassActionLogCleanUpBatch.PHASE_CHILD, 'batchSize below 1');
        assertThrows(30, 2001, toolMassActionLogCleanUpBatch.PHASE_CHILD, 'batchSize above 2000');
        assertThrows(30, 200, 'Invalid', 'invalid phase');
    }

    @IsTest
    static void scheduleCreatesCronJob() {
        Test.startTest();
        String cronJobId = System.schedule('toolMassActionLogCleanUpBatchTEST', '0 0 2 * * ?', new toolMassActionLogCleanUpBatch(30));
        Test.stopTest();

        List<CronTrigger> cronJobs = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :cronJobId];
        Assert.areEqual(1, cronJobs.size(), 'Scheduled job should exist. Cron Id: ' + cronJobId);
        Assert.areEqual('0 0 2 * * ?', cronJobs[0].CronExpression, 'Cron expression should match. Found: ' + cronJobs[0].CronExpression);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static void assertThrows(Integer daysToKeep, Integer batchSize, String phase, String scenario) {
        try {
            new toolMassActionLogCleanUpBatch(daysToKeep, false, batchSize, phase);
            Assert.fail('Expected toolMassActionLogCleanUpException for ' + scenario);
        } catch (toolMassActionLogCleanUpBatch.toolMassActionLogCleanUpException ex) {
            Assert.isTrue(ex.getMessage().contains('toolMassActionLogCleanUpBatch'), 'Exception message should identify the class for ' + scenario + '. Message: ' + ex.getMessage());
        }
    }

    private static Map<String, Mass_Action_Log__c> getRemainingLogs() {
        Map<String, Mass_Action_Log__c> logsByMessage = new Map<String, Mass_Action_Log__c>();
        for (Mass_Action_Log__c logRecord : [SELECT Id, Message__c FROM Mass_Action_Log__c]) {
            logsByMessage.put(logRecord.Message__c, logRecord);
        }
        return logsByMessage;
    }
}