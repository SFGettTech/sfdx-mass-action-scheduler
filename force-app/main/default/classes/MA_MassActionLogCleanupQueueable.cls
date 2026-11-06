/**
 * Author:       Josh Gettman
 * Date:         2026-10-13
 * Description:  Deletes orphaned child Mass Action Logs (Parent_Log__c blanked
 *               by the SetNull lookup) that MA_MassActionLogTriggerHandler
 *               could not cascade delete within the parent delete's DML row
 *               budget. Deletes in chunks and re-enqueues itself until none
 *               remain.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-10-13 | Josh Gettman | Initial build
 * ---------------------------------------------------------------------------
 */
public without sharing class MA_MassActionLogCleanupQueueable implements Queueable {

    @TestVisible
    private static final Integer CHUNK_SIZE = 9000;

    // one enqueue per transaction, no matter how many trigger chunks overflow
    private static Boolean isEnqueued = false;

    public static void enqueue() {
        if ( isEnqueued || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() ) {
            return;
        }
        System.enqueueJob( new MA_MassActionLogCleanupQueueable() );
        isEnqueued = true;
    }

    public void execute( QueueableContext context ) {

        List<Mass_Action_Log__c> orphanLogs = [
            SELECT
                Id
            FROM
                Mass_Action_Log__c
            WHERE
                Parent_Log__c = null
                AND
                RecordType.DeveloperName = 'Child_Log'
            WITH SYSTEM_MODE
            LIMIT :CHUNK_SIZE
        ];

        if ( orphanLogs.isEmpty() ) {
            return;
        }

        Database.delete( orphanLogs, true, AccessLevel.SYSTEM_MODE );

        // chained queueables cannot run in tests
        if ( orphanLogs.size() == CHUNK_SIZE && !Test.isRunningTest() ) {
            enqueue();
        }

    }

}