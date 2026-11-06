/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-08-07
 * Description:  Restore system-mode SOQL and DML after the API 67.0 uplift.
 * Version:      1.2
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-07 | Josh Gettman | Added WITH SYSTEM_MODE / AccessLevel.
 *     |            |              | SYSTEM_MODE so SOQL and DML keep the
 *     |            |              | system-mode default lost at API 67.0.
 * ---------------------------------------------------------------------------
 * 1.1 | 2026-10-12 | Josh Gettman | Added getRunningJob, logSkippedRun and
 *     |            |              | logFailedRun so a scheduled run can skip
 *     |            |              | itself while the previous run of the same
 *     |            |              | configuration is still in progress.
 * ---------------------------------------------------------------------------
 * 1.2 | 2026-11-06 | Josh Gettman | enqueueAction supports Source_Type__c
 *     |            |              | 'NotRequired' via toolNoSourceIterable:
 *     |            |              | the target runs once per run with static
 *     |            |              | mappings only
 * ---------------------------------------------------------------------------
 */
public inherited sharing class MA_MassActionBatchUtils {

    // AsyncApexJob.Status values for a batch job that has not finished.
    private static final Set<String> ACTIVE_JOB_STATUSES = new Set<String>{ 'Holding', 'Queued', 'Preparing', 'Processing' };

    // How many of the configuration's most recent runs to check for one still in progress.
    private static final Integer RUNNING_JOB_LOOKBACK = 5;

    public static ID enqueueAction( ID configId ) {

        Mass_Action_Configuration__c config = MA_MassActionUtils.getConfiguration( configId );

        System.debug( 'MA_MassActionBatchUtils.enqueueAction: ' + config );

        ID jobId = null;

        if ( config.Active__c ) {

            if ( config.Source_Type__c == 'Report' ) {

                jobId = enqueueReportJob( config );

            } else if ( config.Source_Type__c == 'ListView' ) {

                jobId = enqueueListViewJob( config );

            } else if ( config.Source_Type__c == 'SOQL' ) {

                jobId = enqueueSoqlJob( config );

            } else if ( config.Source_Type__c == 'Apex' ) {

                jobId = enqueueApexJob( config );

            } else if ( config.Source_Type__c == toolNoSourceIterable.SOURCE_TYPE ) {

                jobId = enqueueNoSourceJob( config );

            } else {

                throw new MA_Exceptions.UnsupportedSourceTypeException( configId, config.Source_Type__c );

            }

            // Log that the job has been enqueued.
            // All other success/error logs for this job
            // will be saved as child logs to this one.

            Map<String,RecordTypeInfo> logRecordTypeInfosMap = Mass_Action_Log__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();

            // We don't have lookup fields to AsyncApexJob records,
            // so standardizing on the 15 character id, least common denominator.
            // Also, must use string variable type because ID variable type
            // always coerces the assigned value back to 18 characters.
            String jobId15 = String.valueOf( jobId ).left( 15 );

            Mass_Action_Log__c log = new Mass_Action_Log__c(
                RecordTypeId = logRecordTypeInfosMap.get( 'Parent_Log' ).getRecordTypeId(),
                Mass_Action_Configuration__c = configId,
                Job_ID__c = jobId15,
                Submitted_Date__c = DateTime.now(),
                Timestamp__c = String.valueOf( DateTime.now().getTime() ),
                Message__c = 'Batch job enqueued',
                Message_Type__c = 'Informational'
            );

            Database.insert( log, true, AccessLevel.SYSTEM_MODE );

        } else {

            System.debug( LoggingLevel.WARN, 'MA_MassActionBatchUtils.enqueueAction: Not enqueueing inactive configuration' );

        }

        System.debug( 'MA_MassActionBatchUtils.enqueueAction: jobId: ' + jobId );

        return jobId;
    }

    private static ID enqueueReportJob( Mass_Action_Configuration__c config ) {

        return Database.executeBatch( new MA_ReportSourceBatchable( config.Id ), config.Batch_Size__c.intValue() );
    }

    private static ID enqueueListViewJob( Mass_Action_Configuration__c config ) {

        return Database.executeBatch( new MA_ListViewSourceBatchable( config.Id ), config.Batch_Size__c.intValue() );
    }

    private static ID enqueueSoqlJob( Mass_Action_Configuration__c config ) {

        return Database.executeBatch( new MA_IterableSourceBatchable( config.Id, new MA_SoqlSourceIterable( config.Id ) ), config.Batch_Size__c.intValue() );
    }

    private static ID enqueueApexJob( Mass_Action_Configuration__c config ) {

        String namespace = null;
        String className = config.Source_Apex_Class__c;

        Type t = null;

        if ( className.contains( '.' ) ) {
            namespace = config.Source_Apex_Class__c.substringBefore( '.' );
            className = config.Source_Apex_Class__c.substringAfter( '.' );
        }

        t = Type.forName( namespace, className );

        // If don't find type then maybe the class name pattern
        // isn't "namespace.className" but rather "outerClass.innerClass"
        // in the current namespace.
        if ( t == null ) {
            t = Type.forName( null, config.Source_Apex_Class__c );
        }

        // If still don't find the type then either it
        // doesn't exist or isn't accessible by our package.
        if ( t == null ) {
            throw MA_Exceptions.buildException(
                NoDataFoundException.class,
                'No class found for name "' + config.Source_Apex_Class__c + '". If it exists, it may need to be global to be accessible by the Mass Action Scheduler package.'
            );
        }

        Iterable<Map<String, Object>> iterable = (Iterable<Map<String, Object>>) t.newInstance();
        return Database.executeBatch( new MA_IterableSourceBatchable( config.Id, iterable ), config.Batch_Size__c.intValue() );

    }

    /**
     * Source Not Required: the iterable yields a single empty row, so the batch runs one
     * execute() and the target action is invoked exactly once, with inputs supplied only
     * by Static Value mappings. Scope size is fixed at 1 because there is only ever one
     * row, which also means a blank Batch_Size__c cannot break this source type.
     */
    private static ID enqueueNoSourceJob( Mass_Action_Configuration__c config ) {

        return Database.executeBatch( new MA_IterableSourceBatchable( config.Id, new toolNoSourceIterable() ), 1 );
    }

    // ----------------------------------------------------

    /**
     * Returns the batch job of this configuration's run that is still in progress,
     * or null if none is.
     *
     * Every run writes a parent log carrying its batch job id (see enqueueAction), so
     * the configuration's most recent parent logs identify the jobs to check.
     */
    public static AsyncApexJob getRunningJob( ID configId ) {

        Set<ID> jobIds = new Set<ID>();

        for ( Mass_Action_Log__c parentLog : [
            SELECT
                Job_ID__c
            FROM
                Mass_Action_Log__c
            WHERE
                Mass_Action_Configuration__c = :configId
                AND
                RecordType.DeveloperName = 'Parent_Log'
                AND
                Job_ID__c != null
            WITH SYSTEM_MODE
            ORDER BY
                CreatedDate DESC
            LIMIT :RUNNING_JOB_LOOKBACK
        ]) {
            jobIds.add( ID.valueOf( parentLog.Job_ID__c ) );
        }

        if ( jobIds.isEmpty() ) {
            return null;
        }

        for ( AsyncApexJob job : [
            SELECT
                Id, Status, CreatedDate
            FROM
                AsyncApexJob
            WHERE
                Id IN :jobIds
                AND
                Status IN :ACTIVE_JOB_STATUSES
            WITH SYSTEM_MODE
            ORDER BY
                CreatedDate DESC
            LIMIT 1
        ]) {
            return job;
        }

        return null;
    }

    /**
     * Records that a scheduled run was skipped because the previous run is still in progress.
     */
    public static void logSkippedRun( ID configId, AsyncApexJob runningJob ) {

        System.debug( LoggingLevel.WARN, 'MA_MassActionBatchUtils.logSkippedRun: configId=' + configId + ', runningJob=' + runningJob );

        insertRunLog(
            configId,
            'Informational',
            'Scheduled run skipped: the previous run is still in progress',
            'Scheduled run skipped because batch job ' + runningJob.Id + ' from a previous run of this configuration is still ' +
                runningJob.Status + '. The next scheduled run will try again.'
        );

    }

    /**
     * Records that a scheduled run could not be started.
     */
    public static void logFailedRun( ID configId, Exception e ) {

        System.debug( LoggingLevel.ERROR, 'MA_MassActionBatchUtils.logFailedRun: configId=' + configId + ', error=' + e.getMessage() );

        insertRunLog(
            configId,
            'Error',
            'Scheduled run failed to start',
            e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString()
        );

    }

    private static void insertRunLog( ID configId, String messageType, String message, String longMessage ) {

        Map<String, RecordTypeInfo> logRecordTypeInfosMap = Mass_Action_Log__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();

        Mass_Action_Log__c log = new Mass_Action_Log__c(
            RecordTypeId = logRecordTypeInfosMap.get( 'Parent_Log' ).getRecordTypeId(),
            Mass_Action_Configuration__c = configId,
            Submitted_Date__c = DateTime.now(),
            Timestamp__c = String.valueOf( DateTime.now().getTime() ),
            Message__c = MA_StringUtils.abbreviateWithinFieldLength( message, Mass_Action_Log__c.Message__c ),
            Long_Message__c = MA_StringUtils.abbreviateWithinFieldLength( longMessage, Mass_Action_Log__c.Long_Message__c ),
            Message_Type__c = messageType
        );

        Database.insert( log, true, AccessLevel.SYSTEM_MODE );

    }

    // ----------------------------------------------------

    /**
     * Designed to be invoked during the batch start method.
     */
    public static void handleBatchJobStarted( ID configId, ID jobId ) {

        System.debug( 'MA_MassActionBatchUtils.handleBatchJobStarted: configId=' + configId + ', jobId=' + jobId );

        List<Mass_Action_Batch_Apex_Status_Event__e> events = new List<Mass_Action_Batch_Apex_Status_Event__e>{
            new Mass_Action_Batch_Apex_Status_Event__e(
                Job_ID__c = jobId,
                Phase__c = 'START',
                Message_Type__c = 'Informational',
                Message__c = 'Started',
                Long_Message__c = 'Started',
                // Massaging the timestamp for the "start" event to ensure it chronologically always is first.
                // See comments in the getDateTimeWithoutMillis() method for more details.
                Timestamp__c = String.valueOf( getDateTimeWithoutMillis( DateTime.now().addSeconds( -1 ) ).getTime() )
            )
        };

        publish( events );

    }

    /**
     * Designed to be invoked during the batch execute method.
     */
    public static void handleBatchJobExecution( ID configId, ID jobId, Integer jobScopeSize, String jobScope ) {

        System.debug( 'MA_MassActionBatchUtils.handleBatchJobExecution: configId=' + configId + ', jobId=' + jobId );

        List<Mass_Action_Batch_Apex_Status_Event__e> events = new List<Mass_Action_Batch_Apex_Status_Event__e>{
            new Mass_Action_Batch_Apex_Status_Event__e(
                Job_ID__c = jobId,
                Phase__c = 'EXECUTE',
                Message_Type__c = 'Success',
                Message__c = 'Processed ' + jobScopeSize + ' records',
                Long_Message__c = 'Processed ' + jobScopeSize + ' records',
                Job_Scope__c = jobScope,
                Timestamp__c = String.valueOf( DateTime.now().getTime() )
            )
        };

        publish( events );

    }

    /**
     * Designed to be invoked during the batch finish method.
     */
    public static void handleBatchJobFinished( ID configId, ID jobId ) {

        System.debug( 'MA_MassActionBatchUtils.handleBatchJobFinished: configId=' + configId + ', jobId=' + jobId );

        List<Mass_Action_Batch_Apex_Status_Event__e> events = new List<Mass_Action_Batch_Apex_Status_Event__e>{
            new Mass_Action_Batch_Apex_Status_Event__e(
                Job_ID__c = jobId,
                Phase__c = 'FINISH',
                Message_Type__c = 'Informational',
                Message__c = 'Finished',
                Long_Message__c = 'Finished',
                // For the final finish event, I don't want the timestamp milliseconds
                // stripped away, I want them to help ensure it's the last event in the sorted list
                Timestamp__c = String.valueOf( DateTime.now().getTime() )
            )
        };

        publish( events );

        AsyncApexJob job = getJobById( jobId );

        Mass_Action_Configuration__c config = new Mass_Action_Configuration__c(
            Id = configId,
            Last_Run_Completed_Date__c = job.CompletedDate,
            Last_Run_Completed_With_Errors__c = ( String.isNotBlank( job.ExtendedStatus ) || job.NumberOfErrors > 0 )
        );

        Database.update( config, true, AccessLevel.SYSTEM_MODE );

    }

    // ----------------------------------------------------

    /**
     * Returns a map of AsyncApexJob records.
     *
     * Useful in platform event triggers to get a map of related jobs.
     */
    public static Map<ID, AsyncApexJob> getJobsByJobIdMap( Set<ID> jobIds ) {

        Map<ID, AsyncApexJob> jobsMap = new Map<ID, AsyncApexJob>([
            SELECT
                Id, ParentJobId, Status, ExtendedStatus,
                TotalJobItems, JobItemsProcessed, NumberOfErrors,
                CreatedDate, CompletedDate
            FROM
                AsyncApexJob
            WHERE
                Id IN :jobIds
            WITH SYSTEM_MODE
        ]);

        if ( Test.isRunningTest() ) {
            // acrobatics for test coverage and the fact that
            // AsyncApexJob records can't truly be mocked
            for ( ID jobId : jobIds ) {
                AsyncApexJob job = getJobById( jobId );
                if ( job != null ) {
                    jobsMap.put( job.Id, job );
                }
            }
        }

        return jobsMap;
    }

    /**
     * Finds the parent log records associated with each async apex job.
     * Returns a map of job id to parent log record.
     *
     * Useful in platform event triggers to identify the parent log
     * for the job the event is for so can know to update the log
     * or for which log to insert child logs.
     */
    public static Map<ID, Mass_Action_Log__c> getParentLogsByJobIdMap( List<AsyncApexJob> jobs ) {

        // It's possible that the batch error event's job id is
        // a child job of the main batch job that represents the
        // mass action configuration's execution.
        // The parent log record's job id will be a parent job id.
        // So to be able to cross-ref correctly, we need the parent job ids.
        Set<String> parentJobIds = new Set<String>();
        for ( AsyncApexJob job : jobs ) {
            parentJobIds.add( String.valueOf( job.Id ).left( 15 ) );
            parentJobIds.add( String.valueOf( String.isNotBlank( job.ParentJobId ) ? job.ParentJobId : job.Id ).left( 15 ) );
        }

        Map<ID, Mass_Action_Log__c> jobIdToParentLogMap = new Map<ID, Mass_Action_Log__c>();
        for ( Mass_Action_Log__c parentLog : [
            SELECT
                Id, Job_ID__c, Mass_Action_Configuration__c
            FROM
                Mass_Action_Log__c
            WHERE
                Job_ID__c IN :parentJobIds
                AND
                RecordType.DeveloperName = 'Parent_Log'
            WITH SYSTEM_MODE
        ]) {
            jobIdToParentLogMap.put( ID.valueOf( parentLog.Job_ID__c ), parentLog );
        }

        return jobIdToParentLogMap;
    }

    /**
     * Utility function to get apex job details.
     */
    public static AsyncApexJob getJobById( ID jobId ) {

        AsyncApexJob job;

        for ( AsyncApexJob item : [
            SELECT
                Id,
                ParentJobId,
                CreatedDate,
                CompletedDate,
                Status,
                ExtendedStatus,
                TotalJobItems,
                JobItemsProcessed,
                NumberOfErrors
            FROM
                AsyncApexJob
            WHERE
                Id = :jobId
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            job = item;
        }

        if ( Test.isRunningTest() ) {
            // acrobatics for test coverage and the fact that
            // AsyncApexJob records can't truly be mocked
            System.debug( 'MA_MassActionBatchUtils.getJobById: running test, getting mock job for id ' + jobId );
            AsyncApexJob mockJob = MA_AsyncApexJobMock.getJobById( jobId );
            if ( mockJob != null ) {
                job = mockJob;
            }
        }

        return job;
    }

    /**
     * Convenience function to publish events and debug log details about them
     * and ensure the long text field values are abbreviated within max length allowed.
     */
    public static List<Database.SaveResult> publish( List<Mass_Action_Batch_Apex_Status_Event__e> events ) {

        System.debug( 'MA_MassActionBatchUtils.publish: eventsToPublish=' + events.size() );

        // Ensure text fields are within field length limits.
        // Manually need to do this since event publishing doesn't
        // accept a DMLOptions argument to enable field truncation.
        for ( Mass_Action_Batch_Apex_Status_Event__e evt : events ) {
            evt.Message__c = MA_StringUtils.abbreviateWithinFieldLength( evt.Message__c, Mass_Action_Batch_Apex_Status_Event__e.Message__c );
            evt.Long_Message__c = MA_StringUtils.abbreviateWithinFieldLength( evt.Long_Message__c, Mass_Action_Batch_Apex_Status_Event__e.Long_Message__c );
            evt.Job_Scope__c = MA_StringUtils.abbreviateWithinFieldLength( evt.Job_Scope__c, Mass_Action_Batch_Apex_Status_Event__e.Job_Scope__c );
        }

        List<Database.SaveResult> results = EventBus.publish( events );

        System.debug( 'MA_MassActionBatchUtils.publish: saveResults.size=' + results.size() );

        for ( Integer i = 0; i < results.size(); i ++ ) {

            Database.SaveResult result = results[i];
            Mass_Action_Batch_Apex_Status_Event__e evt = events[i];

            System.debug( 'MA_MassActionBatchUtils.publish: operationId=' + EventBus.getOperationId( result ) + ', event: ' + JSON.serializePretty( evt ) );

            if ( !result.isSuccess() ) {
                for ( Database.Error err : result.getErrors() ) {
                    System.debug( LoggingLevel.ERROR, 'MA_MassActionBatchUtils.publish: error: ' + JSON.serializePretty( err ) );
                }
            }

        }

        return results;
    }

    /**
     * Apex DateTime precision supports milliseconds.
     * Platform Event datetimes do not.
     * This means that occasionally the "start" event would
     * sort in the logs AFTER some "execution" events based on the
     * Timestamp__c field. To mitigate this and put things on the
     * same playing field, we truncate the milliseconds from the
     * date/times when set on events from Apex to match the precision
     * of the date/times provided in platform events.
     *
     * For example, see MA_BatchApexErrorEventInvocable when it
     * creates a Mass_Action_Batch_Apex_Status_Event__e and sets the Timestamp__c
     * to evt.CreatedDate. That value's precision won't include milliseconds.
     *
     * https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_events_api_considerations.htm
     */
    private static DateTime getDateTimeWithoutMillis( DateTime dt ) {
        return DateTime.newInstanceGMT(
            Date.newInstance( dt.yearGMT(), dt.monthGMT(), dt.dayGMT() ),
            Time.newInstance( dt.hourGMT(), dt.minuteGMT(), dt.secondGMT(), 0 )
        );
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