/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-08-03
 * Description:  Salesforce API version uplift, 54.0 -> 67.0.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Ran log DML in system mode so the Automated
 *     |            |              | Process user can set record types; added DML
 *     |            |              | error aggregation.
 * ---------------------------------------------------------------------------
 */
/*
 * This class explicitly uses 'without sharing' because it runs not as a real user
 * but rather as the Automated Process user, an entity we can't grant permissions to.
 */
public without sharing class MA_BatchApexStatusEventTriggerHandler {

    public MA_BatchApexStatusEventTriggerHandler() {}

    // -------------------------------------------------------
    // INSERT
    // -------------------------------------------------------

    public void handleAfterInsert( List<Mass_Action_Batch_Apex_Status_Event__e> newList, Map<ID, Mass_Action_Batch_Apex_Status_Event__e> newMap ) {

        System.debug( 'MA_BatchApexStatusEventTriggerHandler.handleAfterInsert' );

        Set<ID> jobIds = new Set<ID>();
        for ( Mass_Action_Batch_Apex_Status_Event__e evt : newList ) {
            if ( String.isNotBlank( evt.Job_ID__c ) ) {
                jobIds.add( ID.valueOf( evt.Job_ID__c ) );
            }
        }

        Map<ID, AsyncApexJob> jobIdToJobMap = MA_MassActionBatchUtils.getJobsByJobIdMap( jobIds );

        Map<ID, Mass_Action_Log__c> jobIdtoParentLogMap = MA_MassActionBatchUtils.getParentLogsByJobIdMap( jobIdToJobMap.values() );

        Map<String, RecordTypeInfo> logRecordTypeInfosMap = Mass_Action_Log__c.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();

        Map<String, Mass_Action_Log__c> parentLogsToUpdateMap = new Map<String, Mass_Action_Log__c>();
        List<Mass_Action_Log__c> childLogsToInsertList = new List<Mass_Action_Log__c>();

        // Platform event triggers may receive up to 2,000 events.
        // Apex triggers are limited to 200 records per batch.
        // Since we are doing DML in this event handler, to mitigate exceeding a governor limit
        // then we'll chunk the events into smaller batches.
        // https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_events_subscribe_batch_resume.htm

        Integer BATCH_LIMIT = 200;
        Integer batchLimitCounter = 0;
        String lastEventReplayId;

        for ( Mass_Action_Batch_Apex_Status_Event__e evt : newList ) {

            batchLimitCounter++;
            if ( batchLimitCounter > BATCH_LIMIT ) {
                System.debug( 'MA_BatchApexStatusEventTriggerHandler.handleAfterInsert: reached batch limit of ' + BATCH_LIMIT + ', will requeue remaining ' + ( newList.size() - BATCH_LIMIT ) + ' events for processing' );
                break;
            }

            System.debug( 'MA_BatchApexStatusEventTriggerHandler.handleAfterInsert: event=' + JSON.serializePretty( evt ) );

            ID asyncApexJobId = ID.valueOf( evt.Job_ID__c );
            AsyncApexJob job = jobIdToJobMap.get( asyncApexJobId );
            Mass_Action_Log__c parentLog = jobIdToParentLogMap.get( asyncApexJobId );

            // if either the job or parent log are null then
            // this batch error event is not for mass action scheduler, skip it
            if ( job != null && parentLog != null ) {

                Mass_Action_Log__c parentLogToUpdate = parentLogsToUpdateMap.get( parentLog.Id );

                if ( parentLogToUpdate == null ) {

                    Boolean jobFailed = ( job.Status == 'Failed' );
                    Boolean jobHasErrors = ( String.isNotBlank( job.ExtendedStatus ) || job.NumberOfErrors > 0 );

                    String messageType = (
                        ( job.Status == 'Aborted' || job.Status == 'Failed' || jobHasErrors ) ? 'Error' :
                        ( job.CompletedDate != null && job.TotalJobItems == job.JobItemsProcessed ) ? 'Success' :
                        'Informational'
                    );

                    String message = 'Batch job ' + (
                        ( job.Status == 'Completed' && jobHasErrors ) ? 'completed with errors' :
                        String.isBlank( job.Status ) ? 'information' :
                        job.Status.toLowerCase()
                    );

                    parentLogsToUpdateMap.put( parentLog.Id, new Mass_Action_Log__c(
                        Id = parentLog.Id,
                        Message_Type__c = messageType,
                        Message__c = message,
                        Submitted_Date__c = job.CreatedDate,
                        Total_Batches__c = job.TotalJobItems,
                        Processed_Batches__c = job.JobItemsProcessed,
                        Failed_Batches__c = job.NumberOfErrors
                    ));

                }

                childLogsToInsertList.add( new Mass_Action_Log__c(
                    RecordTypeId = logRecordTypeInfosMap.get( 'Child_Log' ).getRecordTypeId(),
                    Mass_Action_Configuration__c = parentLog.Mass_Action_Configuration__c,
                    Parent_Log__c = parentLog.Id,
                    Job_ID__c = parentLog.Job_ID__c,
                    Message_Type__c = evt.Message_Type__c,
                    Message__c = evt.Message__c,
                    Long_Message__c = evt.Long_Message__c,
                    Job_Scope__c = evt.Job_Scope__c,
                    Timestamp__c = evt.Timestamp__c
                ));

            }

            lastEventReplayId = evt.ReplayId;

        }

        System.debug( 'MA_BatchApexStatusEventTriggerHandler.handleAfterInsert: inserting child logs and updating parent logs' );

        Database.DMLOptions dmo = new Database.DMLOptions();
        dmo.allowFieldTruncation = true;

        // This handler runs as the Automated Process user, which cannot be granted a
        // permission set and therefore has no record type visibility on Mass_Action_Log__c.
        // That user context is now enforced on DML, so setting RecordTypeId to the
        // 'Child_Log' / 'Parent_Log' record types fails with INVALID_CROSS_REFERENCE_KEY
        // unless the DML runs in system mode. Verified by running identical code at
        // API 54.0 (insert succeeds) and API 67.0 (insert fails) in the same org; the
        // exact release that introduced the enforcement was not determined.
        List<Database.SaveResult> insertResults = Database.insert( childLogsToInsertList, dmo, AccessLevel.SYSTEM_MODE );
        List<Database.SaveResult> updateResults = Database.update( parentLogsToUpdateMap.values(), dmo, AccessLevel.SYSTEM_MODE );

        // These DML calls run with partial success, so failures are silent unless we
        // inspect the results. Aggregate and log them verbosely; we deliberately do not
        // throw, because an uncaught exception in a platform event trigger causes the
        // event batch to be retried and then discarded, losing the status events entirely.
        logDmlErrors( 'insert child logs', childLogsToInsertList, insertResults );
        logDmlErrors( 'update parent logs', parentLogsToUpdateMap.values(), updateResults );

        // When the trigger stops its flow of execution, either intentionally or because of an unhandled exception,
        // such as a limit exception, it fires again with a new batch (the sObject list in Trigger.New).
        // The new batch starts with the event message after the one with the replay ID that you set.
        // Therefore, we don't want to set this resume checkpoint until we know that the above DML operations complete.
        // https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_events_subscribe_batch_resume.htm
        if ( String.isNotBlank( lastEventReplayId ) ) {
            System.debug( 'MA_BatchApexStatusEventTriggerHandler.handleAfterInsert: setting resume checkpoint: lastEventReplayId=' + lastEventReplayId );
            EventBus.TriggerContext.currentContext().setResumeCheckpoint( lastEventReplayId );
        }

    }

    /**
     * Aggregates and logs the errors from a partial-success DML operation.
     * Each failed record is reported with its index, id, status code, offending
     * fields, and message so a failure is diagnosable without a debug trace.
     *
     * @param operation
     *      Human readable description of the DML being performed, used in the log message.
     * @param records
     *      The records the DML was attempted on, positionally aligned with `results`.
     * @param results
     *      The save results returned by the DML call.
     */
    private static void logDmlErrors( String operation, List<Mass_Action_Log__c> records, List<Database.SaveResult> results ) {

        List<String> errors = new List<String>();

        for ( Integer i = 0; i < results.size(); i++ ) {
            if ( !results[i].isSuccess() ) {
                for ( Database.Error err : results[i].getErrors() ) {
                    errors.add( String.format(
                        'Failed to {0} at index {1} (Id: {2}): [{3}] {4} — fields: {5}',
                        new Object[] {
                            operation, i, records[i].Id, err.getStatusCode(), err.getMessage(),
                            String.join( err.getFields(), ', ' )
                        }
                    ));
                }
            }
        }

        if ( !errors.isEmpty() ) {
            System.debug( LoggingLevel.ERROR, 'MA_BatchApexStatusEventTriggerHandler.logDmlErrors: ' + String.join( errors, '\n' ) );
        }

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