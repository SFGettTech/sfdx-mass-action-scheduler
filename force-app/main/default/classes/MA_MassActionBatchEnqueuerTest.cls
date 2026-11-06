/**
 * Author:       Josh Gettman
 * Date:         2026-10-12
 * Description:  Tests for MA_MassActionBatchEnqueuer: interval self-rescheduling,
 *               overlap skipping, and start-failure logging.
 *
 *               These tests call the enqueuer directly, outside Test.startTest() and
 *               Test.stopTest(), on purpose. A batch queued there stays "in progress"
 *               for the rest of the test method, which is what the overlap check needs,
 *               and the rescheduled one-time job does not fire and enqueue a second
 *               batch (a test method may execute only one batch).
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-10-12 | Josh Gettman | Initial build
 * ---------------------------------------------------------------------------
 */
@IsTest
private class MA_MassActionBatchEnqueuerTest {

    private static Mass_Action_Configuration__c insertConfig( String frequency, String intervalMinutes ) {

        // A batch queued by a test still runs when the test method ends, and the
        // list view source describes the list view over REST.
        Test.setMock( HttpCalloutMock.class, new MA_HttpCalloutMock() );

        String objectName = MA_NamespaceUtils.NAMESPACE_API + 'Mass_Action_Configuration__c';
        ListView lv = [ SELECT Id FROM ListView WHERE DeveloperName = 'All' AND SobjectType = :objectName AND IsSoqlCompatible = true LIMIT 1 ];

        Mass_Action_Configuration__c config = new Mass_Action_Configuration__c(
            Name = 'Test Config',
            DeveloperName__c = 'Test_Config',
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Active__c = true,
            Batch_Size__c = 1,
            Source_Type__c = 'ListView',
            Source_List_View_ID__c = lv.Id,
            Target_Type__c = 'Workflow',
            Target_SObject_Type__c = 'Account',
            Schedule_Frequency__c = frequency,
            Schedule_Interval_Minutes__c = intervalMinutes
        );

        insert config;

        insert new Mass_Action_Mapping__c(
            Mass_Action_Configuration__c = config.Id,
            Source_Field_Name__c = 'Id',
            Target_Field_Name__c = 'ContextId'
        );

        return config;
    }

    private static Integer countEnqueuedRuns( ID configId ) {
        return [
            SELECT COUNT() FROM Mass_Action_Log__c
            WHERE Mass_Action_Configuration__c = :configId AND RecordType.DeveloperName = 'Parent_Log' AND Job_ID__c != null
        ];
    }

    private static List<Mass_Action_Log__c> getRunLogsWithoutJob( ID configId ) {
        return [
            SELECT Id, Message__c, Long_Message__c, Message_Type__c FROM Mass_Action_Log__c
            WHERE Mass_Action_Configuration__c = :configId AND RecordType.DeveloperName = 'Parent_Log' AND Job_ID__c = null
        ];
    }

    private static List<CronTrigger> getScheduledJobs( ID configId ) {
        return [ SELECT Id, CronExpression FROM CronTrigger WHERE CronJobDetail.Name = :( 'MA_MassAction_' + configId ) ];
    }

    // ------------------------------------------------------------------------

    @IsTest
    static void test_interval_run_books_next_run_then_enqueues() {

        Mass_Action_Configuration__c config = insertConfig( MA_MassActionScheduleUtils.FREQUENCY_INTERVAL, '15' );

        List<CronTrigger> jobsBefore = getScheduledJobs( config.Id );
        System.assertEquals( 1, jobsBefore.size(), 'inserting an active interval config schedules its first run' );

        new MA_MassActionBatchEnqueuer().execute( null, config.Id );

        List<CronTrigger> jobsAfter = getScheduledJobs( config.Id );
        System.assertEquals( 1, jobsAfter.size(), 'exactly one job stays scheduled' );
        System.assertNotEquals( jobsBefore[0].Id, jobsAfter[0].Id, 'the job that fired is replaced by a job for the next run' );
        System.assertEquals( 1, countEnqueuedRuns( config.Id ), 'the run is enqueued' );

    }

    @IsTest
    static void test_run_is_skipped_and_logged_while_previous_run_in_progress() {

        Mass_Action_Configuration__c config = insertConfig( 'Manual', null );

        // A previous run that is still queued.
        MA_MassActionBatchUtils.enqueueAction( config.Id );
        System.assertNotEquals( null, MA_MassActionBatchUtils.getRunningJob( config.Id ), 'the previous run is in progress' );

        new MA_MassActionBatchEnqueuer().execute( null, config.Id );

        System.assertEquals( 1, countEnqueuedRuns( config.Id ), 'no second run is enqueued' );

        List<Mass_Action_Log__c> skipLogs = getRunLogsWithoutJob( config.Id );
        System.assertEquals( 1, skipLogs.size() );
        System.assertEquals( 'Informational', skipLogs[0].Message_Type__c );
        System.assert( skipLogs[0].Message__c.startsWith( 'Scheduled run skipped' ), skipLogs[0].Message__c );

    }

    @IsTest
    static void test_interval_run_still_reschedules_when_skipped() {

        Mass_Action_Configuration__c config = insertConfig( MA_MassActionScheduleUtils.FREQUENCY_INTERVAL, '5' );

        MA_MassActionBatchUtils.enqueueAction( config.Id );

        new MA_MassActionBatchEnqueuer().execute( null, config.Id );

        System.assertEquals( 1, getScheduledJobs( config.Id ).size(), 'the next run is still booked' );
        System.assertEquals( 1, getRunLogsWithoutJob( config.Id ).size(), 'the skip is logged' );

    }

    @IsTest
    static void test_interval_start_failure_is_logged_not_thrown() {

        Mass_Action_Configuration__c config = insertConfig( MA_MassActionScheduleUtils.FREQUENCY_INTERVAL, '15' );

        // An Apex source class that does not exist makes enqueueAction throw.
        config.Source_Type__c = 'Apex';
        config.Source_Apex_Class__c = 'MA_No_Such_Source_Class_For_Test';
        update config;

        new MA_MassActionBatchEnqueuer().execute( null, config.Id );

        System.assertEquals( 1, getScheduledJobs( config.Id ).size(), 'the next run is still booked' );
        System.assertEquals( 0, countEnqueuedRuns( config.Id ) );

        List<Mass_Action_Log__c> errorLogs = getRunLogsWithoutJob( config.Id );
        System.assertEquals( 1, errorLogs.size() );
        System.assertEquals( 'Error', errorLogs[0].Message_Type__c );
        System.assert( errorLogs[0].Long_Message__c.contains( 'MA_No_Such_Source_Class_For_Test' ), errorLogs[0].Long_Message__c );

    }

    @IsTest
    static void test_inactive_interval_config_is_not_rescheduled() {

        Mass_Action_Configuration__c config = insertConfig( MA_MassActionScheduleUtils.FREQUENCY_INTERVAL, '15' );

        config.Active__c = false;
        update config;

        new MA_MassActionBatchEnqueuer().execute( null, config.Id );

        System.assertEquals( 0, getScheduledJobs( config.Id ).size() );
        System.assertEquals( 0, countEnqueuedRuns( config.Id ), 'inactive configs do not run' );

    }

    @IsTest
    static void test_non_interval_run_enqueues() {

        Mass_Action_Configuration__c config = insertConfig( 'Manual', null );

        new MA_MassActionBatchEnqueuer().execute( null, config.Id );

        System.assertEquals( 1, countEnqueuedRuns( config.Id ) );
        System.assertEquals( 0, getScheduledJobs( config.Id ).size(), 'non-interval runs do not book themselves' );

    }

}