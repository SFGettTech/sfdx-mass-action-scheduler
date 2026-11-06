/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-10-12
 * Description:  Interval scheduling and overlap protection for scheduled runs.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-10-12 | Josh Gettman | An interval ("Repeat Every X Minutes")
 *     |            |              | config books its next run before anything
 *     |            |              | else, and a start failure is logged rather
 *     |            |              | than thrown so it cannot break that chain.
 *     |            |              | Every scheduled run is skipped and logged
 *     |            |              | while the previous run of the same config
 *     |            |              | is still in progress.
 * ---------------------------------------------------------------------------
 */
/*
 * MA_MassActionSchedulable reaches this class through Type.forName, so this class
 * can be changed and deployed while Mass Action jobs are scheduled.
 */
public with sharing class MA_MassActionBatchEnqueuer implements MA_MassActionSchedulable.MA_MassActionSchedulableDispatched {

    public void execute( SchedulableContext context, ID configID ) {

        System.debug( 'MA_MassActionBatchEnqueuer.execute: ' + context );

        Mass_Action_Configuration__c config = MA_MassActionUtils.getConfiguration( configId );

        Boolean isInterval = MA_MassActionScheduleUtils.isInterval( config );

        // An interval config is scheduled one run at a time. Book the next run first so
        // that nothing below, including a skipped or failed run, can stop the repeats.
        if ( isInterval && config.Active__c ) {
            MA_MassActionScheduleUtils.scheduleNextIntervalRun( configId );
        }

        AsyncApexJob runningJob = MA_MassActionBatchUtils.getRunningJob( configId );

        if ( runningJob != null ) {
            MA_MassActionBatchUtils.logSkippedRun( configId, runningJob );
            return;
        }

        if ( isInterval ) {

            // Log instead of throwing: an uncaught exception would roll back the
            // next run booked above and end the repeats.
            try {
                MA_MassActionBatchUtils.enqueueAction( configId );
            } catch ( Exception e ) {
                MA_MassActionBatchUtils.logFailedRun( configId, e );
            }

        } else {

            MA_MassActionBatchUtils.enqueueAction( configId );

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