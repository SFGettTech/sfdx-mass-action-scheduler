/*
 * Author:      Josh Gettman
 * Date:        2026-11-04
 * Description: Deletes Mass_Action_Log__c records older than a given number of days.
 *              Runs in two chained phases to avoid the Parent_Log__c SetNull cascade:
 *                1. Child phase  - deletes old logs that have a Parent_Log__c.
 *                2. Parent phase - deletes old logs with no Parent_Log__c, skipping any
 *                                  parent that still has (newer) child logs.
 *              Cutoff = midnight (running user's time zone) of today minus daysToKeep.
 *              daysToKeep = 0 keeps today's logs only.
 *              Usage (Execute Anonymous):  toolMassActionLogCleanUpBatch.run(30);
 *              Usage (schedule nightly):   System.schedule('Mass Action Log Clean Up',
 *                                              '0 0 2 * * ?', new toolMassActionLogCleanUpBatch(30));
 *              Sharing: 'with sharing'. The running/scheduling user needs Delete plus
 *              Modify All on Mass_Action_Log__c (or Modify All Data) to purge every log.
 * Version:     1.0
 *
 * Modification Log:
 * Ver | Date       | Author       | Modification
 * 1.0 | 2026-11-04 | Josh Gettman | Initial build
 */
public with sharing class toolMassActionLogCleanUpBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    public static final Integer DEFAULT_BATCH_SIZE = 2000;
    @TestVisible private static final String PHASE_CHILD = 'Child';
    @TestVisible private static final String PHASE_PARENT = 'Parent';
    private static final Integer MAX_BATCH_SIZE = 2000;
    private static final Integer MAX_ERROR_LINES = 50;

    private Integer batchSize;
    private Integer daysToKeep;
    private Boolean emptyRecycleBin;
    @TestVisible private Datetime cutoffDate;
    @TestVisible private String phase;
    @TestVisible private Integer deletedCount = 0;
    @TestVisible private Integer failedCount = 0;
    @TestVisible private Integer skippedParentCount = 0;
    @TestVisible private List<String> errorMessages = new List<String>();

    // ------------------------------------------------------------------
    // Constructors
    // ------------------------------------------------------------------

    public toolMassActionLogCleanUpBatch(Integer daysToKeep) {
        this(daysToKeep, false, DEFAULT_BATCH_SIZE, PHASE_CHILD);
    }

    public toolMassActionLogCleanUpBatch(Integer daysToKeep, Boolean emptyRecycleBin, Integer batchSize) {
        this(daysToKeep, emptyRecycleBin, batchSize, PHASE_CHILD);
    }

    @TestVisible
    private toolMassActionLogCleanUpBatch(Integer daysToKeep, Boolean emptyRecycleBin, Integer batchSize, String phase) {
        if (daysToKeep == null || daysToKeep < 0) {
            throw new toolMassActionLogCleanUpException('toolMassActionLogCleanUpBatch: daysToKeep must be 0 or greater. Received: ' + daysToKeep);
        }
        if (batchSize == null || batchSize < 1 || batchSize > MAX_BATCH_SIZE) {
            throw new toolMassActionLogCleanUpException('toolMassActionLogCleanUpBatch: batchSize must be between 1 and ' + MAX_BATCH_SIZE + '. Received: ' + batchSize);
        }
        if (phase != PHASE_CHILD && phase != PHASE_PARENT) {
            throw new toolMassActionLogCleanUpException('toolMassActionLogCleanUpBatch: phase must be ' + PHASE_CHILD + ' or ' + PHASE_PARENT + '. Received: ' + phase);
        }
        this.batchSize = batchSize;
        this.cutoffDate = Datetime.newInstance(System.today().addDays(-daysToKeep), Time.newInstance(0, 0, 0, 0));
        this.daysToKeep = daysToKeep;
        this.emptyRecycleBin = emptyRecycleBin == true;
        this.phase = phase;
    }

    // ------------------------------------------------------------------
    // Convenience entry points (Execute Anonymous)
    // ------------------------------------------------------------------

    public static Id run(Integer daysToKeep) {
        return run(daysToKeep, false, DEFAULT_BATCH_SIZE);
    }

    public static Id run(Integer daysToKeep, Boolean emptyRecycleBin, Integer batchSize) {
        toolMassActionLogCleanUpBatch cleanUpJob = new toolMassActionLogCleanUpBatch(daysToKeep, emptyRecycleBin, batchSize);
        return Database.executeBatch(cleanUpJob, cleanUpJob.batchSize);
    }

    // ------------------------------------------------------------------
    // Schedulable
    // ------------------------------------------------------------------

    public void execute(SchedulableContext sc) {
        // New instance each run so the cutoff is recalculated from the run date
        Database.executeBatch(new toolMassActionLogCleanUpBatch(this.daysToKeep, this.emptyRecycleBin, this.batchSize), this.batchSize);
    }

    // ------------------------------------------------------------------
    // Batchable
    // ------------------------------------------------------------------

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = this.cutoffDate;
        if (this.phase == PHASE_CHILD) {
            return Database.getQueryLocator([
                SELECT Id
                FROM Mass_Action_Log__c
                WHERE CreatedDate < :cutoff
                    AND Parent_Log__c != null
                ORDER BY Mass_Action_Configuration__c
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id
            FROM Mass_Action_Log__c
            WHERE CreatedDate < :cutoff
                AND Parent_Log__c = null
            ORDER BY Mass_Action_Configuration__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        try {
            List<SObject> recordsToDelete = (this.phase == PHASE_PARENT) ? filterParentsWithoutChildren(scope) : scope;
            if (recordsToDelete.isEmpty()) {
                return;
            }

            List<Database.DeleteResult> deleteResults = Database.delete(recordsToDelete, false);
            List<Id> deletedIds = new List<Id>();
            for (Integer i = 0; i < deleteResults.size(); i++) {
                Database.DeleteResult deleteResult = deleteResults[i];
                if (deleteResult.isSuccess()) {
                    deletedIds.add(deleteResult.getId());
                    continue;
                }
                this.failedCount++;
                for (Database.Error deleteError : deleteResult.getErrors()) {
                    recordError('Delete failed for ' + recordsToDelete[i].Id + ' (' + this.phase + ' phase): '
                        + deleteError.getStatusCode() + ' | ' + deleteError.getMessage()
                        + ' | Fields: ' + String.join(deleteError.getFields(), ', '));
                }
            }
            this.deletedCount += deletedIds.size();

            if (this.emptyRecycleBin && !deletedIds.isEmpty()) {
                Database.emptyRecycleBin(deletedIds);
            }
        } catch (Exception ex) {
            recordError('Unexpected ' + ex.getTypeName() + ' in ' + this.phase + ' phase (scope size ' + scope.size() + '): '
                + ex.getMessage() + ' | Line ' + ex.getLineNumber() + ' | ' + ex.getStackTraceString());
        }
    }

    public void finish(Database.BatchableContext bc) {
        try {
            String jobStatus = '';
            if (bc != null) {
                Id jobId = bc.getJobId();
                List<AsyncApexJob> jobRecords = [
                    SELECT Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
                    FROM AsyncApexJob
                    WHERE Id = :jobId
                    LIMIT 1
                ];
                if (!jobRecords.isEmpty()) {
                    jobStatus = ' | Job ' + jobId + ' status ' + jobRecords[0].Status
                        + ' (' + jobRecords[0].JobItemsProcessed + '/' + jobRecords[0].TotalJobItems + ' chunks, '
                        + jobRecords[0].NumberOfErrors + ' chunk errors)';
                }
            }
            System.debug(this.errorMessages.isEmpty() ? LoggingLevel.INFO : LoggingLevel.ERROR, buildSummary(jobStatus));

            // Chain the parent phase after the child phase completes
            if (this.phase == PHASE_CHILD && !Test.isRunningTest()) {
                toolMassActionLogCleanUpBatch parentJob = new toolMassActionLogCleanUpBatch(this.daysToKeep, this.emptyRecycleBin, this.batchSize, PHASE_PARENT);
                parentJob.cutoffDate = this.cutoffDate;
                Database.executeBatch(parentJob, this.batchSize);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'toolMassActionLogCleanUpBatch finish failed in ' + this.phase + ' phase: '
                + ex.getTypeName() + ' | ' + ex.getMessage() + ' | Line ' + ex.getLineNumber() + ' | ' + ex.getStackTraceString());
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    @TestVisible
    private String buildSummary(String jobStatus) {
        String summaryText = 'toolMassActionLogCleanUpBatch [' + this.phase + ' phase] cutoff ' + this.cutoffDate.format()
            + ' | deleted ' + this.deletedCount
            + ' | failed ' + this.failedCount
            + ' | parents kept (newer child logs) ' + this.skippedParentCount
            + jobStatus;
        if (!this.errorMessages.isEmpty()) {
            summaryText += '\nErrors:\n' + String.join(this.errorMessages, '\n');
        }
        return summaryText;
    }

    private List<SObject> filterParentsWithoutChildren(List<SObject> scope) {
        Set<Id> scopeIds = new Map<Id, SObject>(scope).keySet();
        List<Mass_Action_Log__c> parentLogs = [
            SELECT Id, (SELECT Id FROM Mass_Action_Logs__r LIMIT 1)
            FROM Mass_Action_Log__c
            WHERE Id IN :scopeIds
        ];
        List<SObject> deletableParents = new List<SObject>();
        for (Mass_Action_Log__c parentLog : parentLogs) {
            if (parentLog.Mass_Action_Logs__r.isEmpty()) {
                deletableParents.add(parentLog);
            } else {
                this.skippedParentCount++;
            }
        }
        return deletableParents;
    }

    private void recordError(String message) {
        if (this.errorMessages.size() < MAX_ERROR_LINES) {
            this.errorMessages.add(message);
        } else if (this.errorMessages.size() == MAX_ERROR_LINES) {
            this.errorMessages.add('Additional errors truncated after ' + MAX_ERROR_LINES + ' lines.');
        }
    }

    // ------------------------------------------------------------------
    // Exception (helper class at end of file)
    // ------------------------------------------------------------------

    public class toolMassActionLogCleanUpException extends Exception {}
}