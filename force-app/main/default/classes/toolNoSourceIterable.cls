/**
 * Author:       Josh Gettman
 * Date:         2026-11-06
 * Description:  Source for Mass Action Configurations whose Source_Type__c is
 *               'NotRequired' ("Source Not Required"). It reads no records: it
 *               yields exactly one empty row, so MA_IterableSourceBatchable runs a
 *               single execute() and invokes the target action (Flow, invocable
 *               Apex, anonymous Apex, and so on) exactly once per run.
 *
 *               Because the row has no fields, every target input must come from a
 *               'Static Value' field mapping. A 'Source Field' mapping has nothing to
 *               read and fails in MA_MassActionUtils.buildActionInputs with a
 *               NoSourceFieldException naming the missing field, which is logged
 *               against the run like any other mapping error.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-11-06 | Josh Gettman | Initial version
 * ---------------------------------------------------------------------------
 */
public with sharing class toolNoSourceIterable implements Iterable<Map<String, Object>> {

    /**
     * Mass_Action_Configuration__c.Source_Type__c picklist API value that selects this source.
     */
    public static final String SOURCE_TYPE = 'NotRequired';

    /**
     * Returns an iterator over a single, empty source row.
     */
    public Iterator<Map<String, Object>> iterator() {
        return new List<Map<String, Object>>{ new Map<String, Object>() }.iterator();
    }

}
