/**
 * Author:       Josh Gettman
 * Date:         2026-08-03
 * Description:  Tests for toolMassActionFlowInvoker.
 *
 *               Most paths run against a stubbed FlowActionRunner injected through the
 *               @TestVisible seam, so they assert the invoker's own aggregation and error
 *               reporting without depending on a real flow existing in the org. One test
 *               deliberately exercises the real Invocable.Action backed runner to prove
 *               that a missing flow is reported as a per-row failure rather than escaping
 *               as an unhandled exception.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Initial creation.
 * ---------------------------------------------------------------------------
 */
@IsTest
private class toolMassActionFlowInvokerTEST {

    private static final String TEST_FLOW_NAME = 'Test_Flow';

    /**
     * A flow API name that will not exist in any org, used to exercise the real
     * Invocable.Action runner's failure handling.
     */
    private static final String NONEXISTENT_FLOW_NAME = 'tool_No_Such_Flow_ZZZ_20260803';

    // ------------------------------------------------------------------------
    // Stubbed runner paths
    // ------------------------------------------------------------------------

    @IsTest
    static void test_invoke_flow_success_one_interview_per_row() {

        toolMassActionFlowRunnerMock stub = new toolMassActionFlowRunnerMock();
        toolMassActionFlowInvoker.runner = stub;

        List<Map<String, Object>> targetRowMaps = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ContextId' => '001000000000001', 'Amount' => 10 },
            new Map<String, Object>{ 'ContextId' => '001000000000002', 'Amount' => 20 },
            new Map<String, Object>{ 'ContextId' => '001000000000003', 'Amount' => 30 }
        };

        Test.startTest();

        toolMassActionFlowInvoker.invokeFlow( TEST_FLOW_NAME, targetRowMaps );

        Test.stopTest();

        System.assertEquals( 3, stub.invocations.size(), 'expected one interview per target row' );
        System.assertEquals( TEST_FLOW_NAME, stub.flowApiNames[0], 'expected the configured flow to be invoked' );

        // each row's inputs should have been passed through untouched
        System.assertEquals( '001000000000001', stub.invocations[0].get( 'ContextId' ) );
        System.assertEquals( 10, stub.invocations[0].get( 'Amount' ) );
        System.assertEquals( '001000000000003', stub.invocations[2].get( 'ContextId' ) );
        System.assertEquals( 30, stub.invocations[2].get( 'Amount' ) );

    }

    @IsTest
    static void test_invoke_flow_aggregates_row_errors() {

        // fail the row at index 1 only
        toolMassActionFlowRunnerMock stub = new toolMassActionFlowRunnerMock();
        stub.rowIndexesToFail.add( 1 );
        stub.errorMessage = 'SIMULATED FLOW ERROR';
        toolMassActionFlowInvoker.runner = stub;

        List<Map<String, Object>> targetRowMaps = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ContextId' => '001000000000001' },
            new Map<String, Object>{ 'ContextId' => '001000000000002' },
            new Map<String, Object>{ 'ContextId' => '001000000000003' }
        };

        Boolean thrown = false;
        String message = null;

        Test.startTest();

        try {
            toolMassActionFlowInvoker.invokeFlow( TEST_FLOW_NAME, targetRowMaps );
        } catch ( toolMassActionFlowInvoker.FlowInvocationException e ) {
            thrown = true;
            message = e.getMessage();
            System.assertEquals( TEST_FLOW_NAME, e.flowApiName, 'exception should name the flow' );
            System.assertEquals( 3, e.totalRows, 'exception should report the total row count' );
            System.assertEquals( 1, e.failures.size(), 'only the one failing row should be reported' );
            System.assertEquals( 1, e.failures[0].rowIndex, 'the failing row index should be reported' );
        }

        Test.stopTest();

        System.assertEquals( true, thrown, 'expected a FlowInvocationException' );

        // every row is attempted even though one failed, so a bad row cannot mask the others
        System.assertEquals( 3, stub.invocations.size(), 'all rows should still be attempted' );

        // the message must be verbose enough to diagnose without a debug log
        System.assert( message.contains( TEST_FLOW_NAME ), 'message should name the flow: ' + message );
        System.assert( message.contains( 'SIMULATED FLOW ERROR' ), 'message should include the underlying error: ' + message );
        System.assert( message.contains( '001000000000002' ), 'message should identify the failed row inputs: ' + message );
        System.assert( message.contains( 'running user' ), 'message should call out the running user change: ' + message );

    }

    @IsTest
    static void test_invoke_flow_reports_every_failed_row() {

        toolMassActionFlowRunnerMock stub = new toolMassActionFlowRunnerMock();
        stub.rowIndexesToFail.addAll( new List<Integer>{ 0, 1 } );
        toolMassActionFlowInvoker.runner = stub;

        List<Map<String, Object>> targetRowMaps = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ContextId' => '001000000000001' },
            new Map<String, Object>{ 'ContextId' => '001000000000002' }
        };

        Test.startTest();

        try {
            toolMassActionFlowInvoker.invokeFlow( TEST_FLOW_NAME, targetRowMaps );
            System.assert( false, 'expected a FlowInvocationException' );
        } catch ( toolMassActionFlowInvoker.FlowInvocationException e ) {
            System.assertEquals( 2, e.failures.size(), 'both failing rows should be reported' );
            System.assertEquals( 2, e.totalRows );
        }

        Test.stopTest();

    }

    @IsTest
    static void test_invoke_flow_blank_name_throws() {

        toolMassActionFlowRunnerMock stub = new toolMassActionFlowRunnerMock();
        toolMassActionFlowInvoker.runner = stub;

        List<Map<String, Object>> targetRowMaps = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ContextId' => '001000000000001' }
        };

        Test.startTest();

        for ( String blankName : new List<String>{ null, '', '   ' } ) {

            Boolean thrown = false;

            try {
                toolMassActionFlowInvoker.invokeFlow( blankName, targetRowMaps );
            } catch ( toolMassActionFlowInvoker.FlowInvocationException e ) {
                thrown = true;
                System.assert(
                    e.getMessage().contains( 'Target Action Name' ),
                    'message should tell the admin which field to fix: ' + e.getMessage()
                );
            }

            System.assertEquals( true, thrown, 'expected a FlowInvocationException for name: "' + blankName + '"' );

        }

        Test.stopTest();

        System.assertEquals( 0, stub.invocations.size(), 'no interview should run when the flow name is blank' );

    }

    @IsTest
    static void test_invoke_flow_empty_input_is_a_no_op() {

        toolMassActionFlowRunnerMock stub = new toolMassActionFlowRunnerMock();
        toolMassActionFlowInvoker.runner = stub;

        Test.startTest();

        // neither a null list nor an empty list should invoke anything or throw
        toolMassActionFlowInvoker.invokeFlow( TEST_FLOW_NAME, null );
        toolMassActionFlowInvoker.invokeFlow( TEST_FLOW_NAME, new List<Map<String, Object>>() );

        Test.stopTest();

        System.assertEquals( 0, stub.invocations.size(), 'no interview should run for empty input' );

    }

    @IsTest
    static void test_invoke_flow_null_row_is_treated_as_empty_inputs() {

        toolMassActionFlowRunnerMock stub = new toolMassActionFlowRunnerMock();
        toolMassActionFlowInvoker.runner = stub;

        List<Map<String, Object>> targetRowMaps = new List<Map<String, Object>>{ null };

        Test.startTest();

        toolMassActionFlowInvoker.invokeFlow( TEST_FLOW_NAME, targetRowMaps );

        Test.stopTest();

        System.assertEquals( 1, stub.invocations.size(), 'a null row should still be invoked' );
        System.assertEquals( 0, stub.invocations[0].size(), 'a null row should become empty inputs, not a null map' );

    }

    @IsTest
    static void test_invoke_flow_null_result_from_runner_is_a_failure() {

        // a runner that returns null must not produce a NullPointerException
        toolMassActionFlowInvoker.runner = new NullReturningRunner();

        List<Map<String, Object>> targetRowMaps = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ContextId' => '001000000000001' }
        };

        Test.startTest();

        try {
            toolMassActionFlowInvoker.invokeFlow( TEST_FLOW_NAME, targetRowMaps );
            System.assert( false, 'expected a FlowInvocationException' );
        } catch ( toolMassActionFlowInvoker.FlowInvocationException e ) {
            System.assertEquals( 1, e.failures.size() );
            System.assert(
                e.getMessage().contains( 'no result' ),
                'message should explain the runner returned nothing: ' + e.getMessage()
            );
        }

        Test.stopTest();

    }

    // ------------------------------------------------------------------------
    // Real Invocable.Action runner
    // ------------------------------------------------------------------------

    /**
     * Exercises the real, non-stubbed runner against a flow that does not exist.
     * The runner must convert that into a reported per-row failure rather than letting
     * the exception escape, so that one misconfigured row is surfaced with the others.
     */
    @IsTest
    static void test_real_runner_missing_flow_reports_row_failure() {

        // deliberately do NOT stub the runner; use the shipped Invocable.Action implementation
        System.assert(
            toolMassActionFlowInvoker.runner instanceof toolMassActionFlowInvoker.InvocableActionRunner,
            'this test must run against the real Invocable.Action runner'
        );

        List<Map<String, Object>> targetRowMaps = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ContextId' => '001000000000001' }
        };

        Boolean thrown = false;

        Test.startTest();

        try {
            toolMassActionFlowInvoker.invokeFlow( NONEXISTENT_FLOW_NAME, targetRowMaps );
        } catch ( toolMassActionFlowInvoker.FlowInvocationException e ) {
            thrown = true;
            System.assertEquals( NONEXISTENT_FLOW_NAME, e.flowApiName );
            System.assertEquals( 1, e.failures.size(), 'the missing flow should be reported as a row failure' );
            System.assert(
                !e.failures[0].errors.isEmpty(),
                'the row failure should carry error detail explaining why the flow could not run'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true, thrown,
            'invoking a nonexistent flow should surface as a FlowInvocationException, ' +
            'not as an unhandled exception from Invocable.Action'
        );

    }

    /**
     * The real runner must report a failure rather than throw, so calling it directly
     * for a nonexistent flow returns an unsuccessful result with detail.
     */
    @IsTest
    static void test_real_runner_returns_failed_result_instead_of_throwing() {

        toolMassActionFlowInvoker.InvocableActionRunner realRunner = new toolMassActionFlowInvoker.InvocableActionRunner();

        Test.startTest();

        toolMassActionFlowInvoker.FlowRowResult result = realRunner.runFlow(
            NONEXISTENT_FLOW_NAME,
            new Map<String, Object>{ 'ContextId' => '001000000000001' }
        );

        Test.stopTest();

        System.assertNotEquals( null, result, 'the runner should always return a result' );
        System.assertEquals( false, result.isSuccess, 'a nonexistent flow should not report success' );
        System.assert( !result.errors.isEmpty(), 'a failed result should carry error detail' );

    }

    // ------------------------------------------------------------------------
    // Test doubles
    // ------------------------------------------------------------------------

    /**
     * Returns null to prove the invoker tolerates a misbehaving runner.
     */
    private class NullReturningRunner implements toolMassActionFlowInvoker.FlowActionRunner {

        public toolMassActionFlowInvoker.FlowRowResult runFlow( String flowApiName, Map<String, Object> inputs ) {
            return null;
        }

    }

}
