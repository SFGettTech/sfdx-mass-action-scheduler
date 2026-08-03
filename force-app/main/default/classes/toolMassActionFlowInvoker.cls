/**
 * Author:       Josh Gettman
 * Date:         2026-08-03
 * Description:  Invokes a target autolaunched flow in-transaction, one interview per
 *               target row, using Invocable.Action rather than the REST Actions API.
 *
 *               Mass Action Scheduler normally invokes non-Apex targets through the
 *               REST Actions API via a Named Credential. A flow reached that way runs
 *               inside a callout, so it cannot perform HTTP callouts of its own. Running
 *               the flow in-transaction lifts that restriction, which is the reason this
 *               un-namespaced fork exists.
 *
 *               Two consequences of running in-transaction, both intentional:
 *                 1. The flow runs as the batch job's running user, NOT as the identity
 *                    configured on the Named Credential.
 *                 2. The flow shares this transaction's governor limits, and a flow that
 *                    performs a callout will consume a callout from this transaction.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Initial creation.
 * ---------------------------------------------------------------------------
 */
public with sharing class toolMassActionFlowInvoker {

    /**
     * The runner used to invoke each flow interview. Defaults to the real
     * Invocable.Action backed implementation; tests swap in a stub.
     */
    @TestVisible
    private static FlowActionRunner runner = new InvocableActionRunner();

    // ------------------------------------------------------------------------

    /**
     * Invokes the given flow once per target row map, in the current transaction.
     *
     * Every row is attempted even if an earlier row fails, so that one bad row does not
     * hide the outcome of the rest of the batch. If any row fails, a single exception
     * naming the flow and listing every failed row is thrown after all rows are attempted.
     *
     * @param flowApiName
     *      API name of the autolaunched flow to invoke. Required.
     * @param targetRowMaps
     *      One map per flow interview. Each key is a flow input variable name and each
     *      value is the value to assign to it. A null or empty list is a no-op.
     *
     * @throws FlowInvocationException
     *      If `flowApiName` is blank, or if any interview reports a failure.
     */
    public static void invokeFlow( String flowApiName, List<Map<String, Object>> targetRowMaps ) {

        System.debug( 'toolMassActionFlowInvoker.invokeFlow: flowApiName=' + flowApiName );

        if ( String.isBlank( flowApiName ) ) {
            throw new FlowInvocationException(
                'Cannot invoke flow: no target flow API name was provided. ' +
                'Check that the Mass Action Configuration\'s "Target Action Name" is populated ' +
                'and that its "Target Type" is "Flow".'
            );
        }

        if ( targetRowMaps == null || targetRowMaps.isEmpty() ) {
            System.debug( 'toolMassActionFlowInvoker.invokeFlow: no target rows to process for flow "' + flowApiName + '", nothing to do' );
            return;
        }

        List<FlowRowFailure> failures = new List<FlowRowFailure>();

        for ( Integer i = 0; i < targetRowMaps.size(); i++ ) {

            Map<String, Object> inputs = targetRowMaps[i];

            if ( inputs == null ) {
                inputs = new Map<String, Object>();
            }

            FlowRowResult result = runner.runFlow( flowApiName, inputs );

            if ( result == null ) {
                failures.add( new FlowRowFailure(
                    i, inputs, new List<String>{ 'The flow action runner returned no result.' }
                ));
            } else if ( !result.isSuccess ) {
                failures.add( new FlowRowFailure( i, inputs, result.errors ) );
            }

        }

        if ( !failures.isEmpty() ) {
            throw new FlowInvocationException( flowApiName, targetRowMaps.size(), failures );
        }

        System.debug( 'toolMassActionFlowInvoker.invokeFlow: invoked flow "' + flowApiName + '" for ' + targetRowMaps.size() + ' row(s) successfully' );

    }

    /**
     * Builds the verbose message for a failed batch of interviews.
     * Lives on the outer class because Apex does not permit static methods on inner classes.
     */
    private static String buildFailureMessage( String flowApiName, Integer totalRows, List<FlowRowFailure> failures ) {

        List<String> described = new List<String>();

        for ( FlowRowFailure failure : failures ) {
            described.add( failure.describe() );
        }

        return String.format(
            'Flow "{0}" failed for {1} of {2} row(s). Each row is invoked as a separate ' +
            'interview in the batch job\'s transaction, running as the batch job\'s running ' +
            'user rather than the Named Credential identity. Failures:\n{3}',
            new Object[] {
                flowApiName,
                String.valueOf( failures.size() ),
                String.valueOf( totalRows ),
                String.join( described, '\n' )
            }
        );

    }

    // ------------------------------------------------------------------------
    // Inner types
    // ------------------------------------------------------------------------

    /**
     * Seam for invoking a single flow interview. Implemented for real by
     * `InvocableActionRunner` and stubbed by tests.
     */
    public interface FlowActionRunner {

        /**
         * Runs one interview of the given flow with the given input variables.
         * Implementations must not throw; a failure is reported on the returned result.
         *
         * @param flowApiName
         *      API name of the flow to invoke.
         * @param inputs
         *      Flow input variable names to values. Never null.
         *
         * @return Outcome of this single interview.
         */
        FlowRowResult runFlow( String flowApiName, Map<String, Object> inputs );

    }

    /**
     * Default runner. Invokes the flow in-transaction through Invocable.Action.
     *
     * A flow that does not exist does NOT raise an exception: `invoke()` returns a result
     * whose `isSuccess()` is false, carrying an error such as
     * `[MISSING_RECORD] Action name not found: <name>`. That is the path a misconfigured
     * Target Action Name actually takes, and it is covered by the tests.
     *
     * The try/catch is a defensive backstop for anything that does raise, for example a
     * governor limit tripped by the flow itself. Either way the row is reported as a
     * failure rather than aborting the batch, so one bad row cannot hide the others.
     */
    public class InvocableActionRunner implements FlowActionRunner {

        public FlowRowResult runFlow( String flowApiName, Map<String, Object> inputs ) {

            FlowRowResult result = new FlowRowResult();

            try {

                Invocable.Action action = Invocable.Action.createCustomAction( 'flow', flowApiName );

                for ( String inputName : inputs.keySet() ) {
                    action.setInvocationParameter( inputName, inputs.get( inputName ) );
                }

                List<Invocable.Action.Result> actionResults = action.invoke();

                if ( actionResults == null || actionResults.isEmpty() ) {
                    result.isSuccess = false;
                    result.errors.add( 'Flow "' + flowApiName + '" returned no invocation result.' );
                    return result;
                }

                for ( Invocable.Action.Result actionResult : actionResults ) {
                    if ( !actionResult.isSuccess() ) {
                        result.isSuccess = false;
                        for ( Invocable.Action.Error err : actionResult.getErrors() ) {
                            result.errors.add( '[' + err.getCode() + '] ' + err.getMessage() );
                        }
                    }
                }

            } catch ( Exception e ) {

                result.isSuccess = false;
                result.errors.add( String.format(
                    '{0}: {1} (line {2})',
                    new Object[] { e.getTypeName(), e.getMessage(), String.valueOf( e.getLineNumber() ) }
                ));

            }

            return result;
        }

    }

    /**
     * Outcome of a single flow interview.
     */
    public class FlowRowResult {

        public Boolean isSuccess { get; set; }

        public List<String> errors { get; set; }

        public FlowRowResult() {
            this.isSuccess = true;
            this.errors = new List<String>();
        }

        public FlowRowResult( Boolean isSuccess, List<String> errors ) {
            this.isSuccess = isSuccess;
            this.errors = ( errors == null ? new List<String>() : errors );
        }

    }

    /**
     * A single row that failed, retained so the thrown exception can name it.
     */
    public class FlowRowFailure {

        public Integer rowIndex { get; set; }

        public Map<String, Object> inputs { get; set; }

        public List<String> errors { get; set; }

        public FlowRowFailure( Integer rowIndex, Map<String, Object> inputs, List<String> errors ) {
            this.rowIndex = rowIndex;
            this.inputs = inputs;
            this.errors = ( errors == null ? new List<String>() : errors );
        }

        public String describe() {
            return String.format(
                'row {0} (inputs: {1}) -> {2}',
                new Object[] {
                    String.valueOf( this.rowIndex ),
                    JSON.serialize( this.inputs ),
                    ( this.errors.isEmpty() ? 'no error detail reported' : String.join( this.errors, '; ' ) )
                }
            );
        }

    }

    /**
     * Thrown when the target flow cannot be invoked, or when one or more
     * interviews report a failure.
     */
    public class FlowInvocationException extends Exception {

        public String flowApiName { get; set; }

        public Integer totalRows { get; set; }

        public List<FlowRowFailure> failures { get; set; }

        public FlowInvocationException( String flowApiName, Integer totalRows, List<FlowRowFailure> failures ) {

            this.flowApiName = flowApiName;
            this.totalRows = totalRows;
            this.failures = failures;

            this.setMessage( buildFailureMessage( flowApiName, totalRows, failures ) );

        }

    }

}
