/**
 * Author:       Josh Gettman
 * Date:         2026-11-06
 * Description:  Tests for toolNoSourceIterable and the 'NotRequired' ("Source Not
 *               Required") branch of MA_MassActionBatchUtils.enqueueAction.
 *
 *               The end-to-end test stubs the flow runner through the @TestVisible
 *               toolMassActionFlowInvoker.runner seam, the same way
 *               MA_IterableSourceBatchableTest does, so no real flow is needed.
 *               Whether the static value reaches the target is asserted against
 *               MA_MassActionUtils.buildActionInputs directly rather than by reading
 *               the stub back after the asynchronous batch finishes.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-11-06 | Josh Gettman | Initial version
 * ---------------------------------------------------------------------------
 */
@IsTest
private class toolNoSourceIterableTEST {

    private static final String TEST_FLOW_NAME = 'Test_Flow';
    private static final String TARGET_FIELD_NAME = 'recordName';
    private static final String STATIC_VALUE = 'Scheduled without a source';

    private static Mass_Action_Configuration__c buildNoSourceConfiguration() {

        return new Mass_Action_Configuration__c(
            Name = 'No Source Config',
            DeveloperName__c = 'No_Source_Config',
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Active__c = true,
            Batch_Size__c = 200,
            Source_Type__c = toolNoSourceIterable.SOURCE_TYPE,
            Target_Type__c = 'Flow',
            Target_Action_Name__c = TEST_FLOW_NAME,
            Schedule_Frequency__c = 'Manual'
        );

    }

    private static Mass_Action_Mapping__c buildStaticMapping( ID configId ) {

        return new Mass_Action_Mapping__c(
            Mass_Action_Configuration__c = configId,
            Mapping_Type__c = MA_MassActionUtils.MAPPING_TYPE_STATIC_VALUE,
            Source_Value__c = STATIC_VALUE,
            Target_Field_Name__c = TARGET_FIELD_NAME
        );

    }

    // ------------------------------------------------------------------------

    @IsTest
    static void iterator_yields_exactly_one_empty_row() {

        Iterator<Map<String, Object>> rows = new toolNoSourceIterable().iterator();

        System.assert( rows.hasNext(), 'toolNoSourceIterable should yield one row so the target runs once per run, but it yielded none.' );

        Map<String, Object> row = rows.next();

        System.assertNotEquals( null, row, 'The single source row should be an empty map, not null.' );
        System.assert( row.isEmpty(), 'The single source row should have no fields, but it had: ' + row.keySet() );
        System.assert( !rows.hasNext(), 'toolNoSourceIterable should yield exactly one row, but it yielded more.' );

    }

    @IsTest
    static void static_mapping_supplies_target_input_without_a_source() {

        List<Map<String, Object>> sourceRows = new List<Map<String, Object>>();
        for ( Map<String, Object> row : new toolNoSourceIterable() ) {
            sourceRows.add( row );
        }

        List<Map<String, Object>> targetRows = MA_MassActionUtils.buildActionInputs(
            sourceRows,
            new List<Mass_Action_Mapping__c>{ buildStaticMapping( null ) }
        );

        System.assertEquals( 1, targetRows.size(), 'One source row should produce one target row.' );
        System.assertEquals( STATIC_VALUE, targetRows[0].get( TARGET_FIELD_NAME ), 'The static value should be passed to the target input unchanged.' );

    }

    @IsTest
    static void source_field_mapping_fails_without_a_source() {

        Mass_Action_Mapping__c sourceFieldMapping = new Mass_Action_Mapping__c(
            Mapping_Type__c = MA_MassActionUtils.MAPPING_TYPE_SOURCE_FIELD,
            Source_Field_Name__c = 'Id',
            Target_Field_Name__c = TARGET_FIELD_NAME
        );

        Boolean threw = false;

        try {
            MA_MassActionUtils.buildActionInputs(
                new List<Map<String, Object>>{ new Map<String, Object>() },
                new List<Mass_Action_Mapping__c>{ sourceFieldMapping }
            );
        } catch ( MA_Exceptions.NoSourceFieldException ex ) {
            threw = true;
        }

        System.assert( threw, 'A Source Field mapping has no field to read when the source is not required, so buildActionInputs should throw NoSourceFieldException.' );

    }

    @IsTest
    static void enqueue_runs_flow_target_once_with_no_source() {

        Mass_Action_Configuration__c config = buildNoSourceConfiguration();
        insert config;
        insert buildStaticMapping( config.Id );

        // The Flow target runs in-transaction; stub the runner so no real flow is needed.
        toolMassActionFlowInvoker.runner = new toolMassActionFlowRunnerMock();

        Test.startTest();

        ID jobId = MA_MassActionBatchUtils.enqueueAction( config.Id );

        Test.stopTest();

        System.assertNotEquals( null, jobId, 'enqueueAction should start a batch job for a Source Not Required configuration.' );

        AsyncApexJob job = MA_MassActionBatchUtils.getJobById( jobId );
        System.assertEquals( 1, job.TotalJobItems, 'A Source Not Required run should process exactly one batch, but processed ' + job.TotalJobItems + '.' );

        config = [
            SELECT Id, Last_Run_Completed_Date__c, Last_Run_Completed_With_Errors__c
            FROM Mass_Action_Configuration__c
            WHERE Id = :config.Id
        ];

        List<Mass_Action_Log__c> errorLogs = [
            SELECT Id, Message__c, Long_Message__c
            FROM Mass_Action_Log__c
            WHERE Mass_Action_Configuration__c = :config.Id
            AND Message_Type__c = 'Error'
        ];

        System.assertEquals( 0, errorLogs.size(), 'A Source Not Required run should log no errors, but logged: ' + errorLogs );
        System.assertEquals( job.CompletedDate, config.Last_Run_Completed_Date__c, 'The configuration should record when the run completed.' );
        System.assertEquals( false, config.Last_Run_Completed_With_Errors__c, 'The run should complete without errors.' );

    }

}
