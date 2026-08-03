/**
 * Author:       Josh Gettman
 * Date:         2026-08-03
 * Description:  Shared test double for toolMassActionFlowInvoker.FlowActionRunner.
 *
 *               Records every interview it is asked to run and reports success or failure
 *               on demand, so tests can exercise the Flow target path without a real flow
 *               existing in the org.
 *
 *               Follows the same pattern as the existing MA_HttpCalloutMock and
 *               MA_AsyncApexJobMock classes: a test double shipped as a regular class so
 *               that more than one test class can share it.
 *
 *               Install it through the invoker's @TestVisible seam:
 *                   toolMassActionFlowInvoker.runner = new toolMassActionFlowRunnerMock();
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Initial creation.
 * ---------------------------------------------------------------------------
 */
public with sharing class toolMassActionFlowRunnerMock implements toolMassActionFlowInvoker.FlowActionRunner {

    /**
     * The input map of every interview this mock was asked to run, in order.
     */
    public List<Map<String, Object>> invocations { get; set; }

    /**
     * The flow API name of every interview this mock was asked to run, in order.
     */
    public List<String> flowApiNames { get; set; }

    /**
     * Zero based row indexes that should report a failure. Empty means every row succeeds.
     */
    public Set<Integer> rowIndexesToFail { get; set; }

    /**
     * Error message reported for a failing row.
     */
    public String errorMessage { get; set; }

    private Boolean defaultSuccess;

    /**
     * Creates a mock where every row succeeds.
     */
    public toolMassActionFlowRunnerMock() {
        this( true );
    }

    /**
     * @param defaultSuccess
     *      Whether a row that is not named in `rowIndexesToFail` should succeed.
     */
    public toolMassActionFlowRunnerMock( Boolean defaultSuccess ) {
        this.defaultSuccess = defaultSuccess;
        this.invocations = new List<Map<String, Object>>();
        this.flowApiNames = new List<String>();
        this.rowIndexesToFail = new Set<Integer>();
        this.errorMessage = 'STUBBED FAILURE';
    }

    /**
     * Records the interview and reports the configured outcome.
     * Never invokes a real flow.
     */
    public toolMassActionFlowInvoker.FlowRowResult runFlow( String flowApiName, Map<String, Object> inputs ) {

        Integer rowIndex = this.invocations.size();

        this.invocations.add( inputs );
        this.flowApiNames.add( flowApiName );

        if ( this.rowIndexesToFail.contains( rowIndex ) || !this.defaultSuccess ) {
            return new toolMassActionFlowInvoker.FlowRowResult(
                false, new List<String>{ this.errorMessage }
            );
        }

        return new toolMassActionFlowInvoker.FlowRowResult();
    }

}
