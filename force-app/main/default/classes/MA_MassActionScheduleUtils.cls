/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-08-07
 * Description:  Restore system-mode SOQL after the API 67.0 uplift.
 * Version:      1.1
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-07 | Josh Gettman | Added WITH SYSTEM_MODE / AccessLevel.
 *     |            |              | SYSTEM_MODE so SOQL and DML keep the
 *     |            |              | system-mode default lost at API 67.0.
 * ---------------------------------------------------------------------------
 * 1.1 | 2026-10-12 | Josh Gettman | Added the 'Interval' ("Repeat Every X
 *     |            |              | Minutes") frequency. Cron cannot express a
 *     |            |              | sub-hourly repeat, so an interval config is
 *     |            |              | scheduled as a one-time job for its next run
 *     |            |              | and MA_MassActionBatchEnqueuer books the run
 *     |            |              | after that each time it fires. Runs may be
 *     |            |              | limited to selected hours and weekdays.
 * ---------------------------------------------------------------------------
 */
/**
 * Most code coverage comes from MA_JobChangeEventTriggerHandlerTest
 */
public inherited sharing class MA_MassActionScheduleUtils {

    // Mass_Action_Configuration__c.Schedule_Frequency__c value for "Repeat Every X Minutes".
    public static final String FREQUENCY_INTERVAL = 'Interval';

    // Schedule_Interval_Minutes__c must be a multiple of this, between the min and max.
    public static final Integer INTERVAL_STEP_MINUTES = 5;
    public static final Integer INTERVAL_MIN_MINUTES = 5;
    public static final Integer INTERVAL_MAX_MINUTES = 60;

    // A run is never booked closer to "now" than this, so System.schedule cannot be
    // handed a fire time that has already passed by the time the call executes.
    private static final Integer INTERVAL_SCHEDULE_BUFFER_SECONDS = 5;

    // Upper bound on the search for the next allowed run. The search jumps a whole hour
    // at a time through excluded hours, so a week of hours plus slack always suffices.
    private static final Integer INTERVAL_MAX_SEARCH_STEPS = ( 8 * 24 ) + 2;

    // Cron weekday tokens, indexed 0 = Sunday. Matches the values the wizard saves.
    private static final List<String> WEEKDAY_TOKENS = new List<String>{ 'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT' };

    // A known Sunday, used to work out the weekday of a date without locale-dependent formatting.
    private static final Date KNOWN_SUNDAY = Date.newInstance( 1900, 1, 7 );

    public static void unscheduleMassActions( List<ID> configIds ) {

        System.debug( 'MA_MassActionScheduleUtils.unscheduleMassActions: ' + configIds );

        configIds = ( configIds == null ? new List<ID>() : configIds );

        Set<String> jobNames = new Set<String>();
        for ( ID configId : configIds ) {
            // Due to oddity with JSON roundtrip serialization of IDs
            // ending up as 15-char IDs instead of 18-char IDs, then
            // explicitly converting the value to an ID to get back to 18-char version.
            // Otherwise, our SOQL query won't find the job names.
            // https://releasenotes.docs.salesforce.com/en-us/winter16/release-notes/rn_apex_json_ids.htm
            jobNames.add( 'MA_MassAction_' + ID.valueOf( configId ) );
        }

        for ( List<CronTrigger> cronTriggers : [
            SELECT
                Id, State, CronJobDetail.Name
            FROM
                CronTrigger
            WHERE
                CronJobDetail.Name IN :jobNames
            WITH SYSTEM_MODE
        ]) {

            for ( CronTrigger cronTrigger : cronTriggers ) {

                System.debug( 'MA_MassActionScheduleUtils.unscheduleMassActions: Aborting job: ' + JSON.serializePretty( cronTrigger ) );
                System.abortJob( cronTrigger.Id );

            }

        }

    }

    public static void scheduleMassActions( List<ID> configIds ) {

        System.debug( 'MA_MassActionScheduleUtils.scheduleMassActions: ' + configIds );

        configIds = ( configIds == null ? new List<ID>() : configIds );

        List<Mass_Action_Configuration__c> configs = new List<Mass_Action_Configuration__c>([
            SELECT
                Id,
                Schedule_Cron__c,
                Schedule_Frequency__c,
                Schedule_SecondOfMinute__c,
                Schedule_MinuteOfHour__c,
                Schedule_HourOfDay__c,
                Schedule_DayOfMonth__c,
                Schedule_MonthOfYear__c,
                Schedule_DayOfWeek__c,
                Schedule_Interval_Minutes__c
            FROM
                Mass_Action_Configuration__c
            WHERE
                Id IN :configIds
            WITH SYSTEM_MODE
        ]);

        for ( Mass_Action_Configuration__c config : configs ) {

            String jobName = 'MA_MassAction_' + config.Id;
            String cron = buildCron( config );

            System.debug( 'MA_MassActionScheduleUtils.scheduleMassActions: Scheduling job: jobName=' + jobName + ', cron=' + cron );
            ID jobId = System.schedule( jobName, cron, new MA_MassActionSchedulable( config.Id ) );
            System.debug( 'MA_MassActionScheduleUtils.scheduleMassActions: Scheduled job: ' + jobId );

        }

    }

    public static String buildCron( Mass_Action_Configuration__c config ) {

        System.debug( 'MA_MassActionScheduleUtils.buildCron: ' + config );

        String cron = '';

        if ( config.Schedule_Frequency__c == 'Scheduled' ) {

            cron = String.format(
                '{0} {1} {2} {3} {4} {5}',
                new String[] {
                    config.Schedule_SecondOfMinute__c,
                    config.Schedule_MinuteOfHour__c,
                    config.Schedule_HourOfDay__c,
                    config.Schedule_DayOfMonth__c,
                    config.Schedule_MonthOfYear__c,
                    config.Schedule_DayOfWeek__c
                }
            );

        } else if ( config.Schedule_Frequency__c == 'Custom' ) {

            cron = config.Schedule_Cron__c;

        } else if ( config.Schedule_Frequency__c == FREQUENCY_INTERVAL ) {

            // A one-time cron for the next run only. The run after that is booked by
            // MA_MassActionBatchEnqueuer when this one fires.
            cron = buildOneTimeCron( getNextIntervalRunTime( config, DateTime.now().addSeconds( INTERVAL_SCHEDULE_BUFFER_SECONDS ) ) );

        }

        System.debug( 'MA_MassActionScheduleUtils.buildCron: cron=' + cron );

        return cron;
    }

    // ------------------------------------------------------------------------
    // Interval ("Repeat Every X Minutes") scheduling
    // ------------------------------------------------------------------------

    public static Boolean isInterval( Mass_Action_Configuration__c config ) {
        return ( config != null && config.Schedule_Frequency__c == FREQUENCY_INTERVAL );
    }

    /**
     * Replaces the configuration's scheduled job with a one-time job for its next
     * interval run. Called by MA_MassActionBatchEnqueuer each time an interval run fires,
     * which also removes the one-time job that just fired.
     */
    public static void scheduleNextIntervalRun( ID configId ) {

        System.debug( 'MA_MassActionScheduleUtils.scheduleNextIntervalRun: ' + configId );

        List<ID> configIds = new List<ID>{ configId };

        unscheduleMassActions( configIds );
        scheduleMassActions( configIds );

    }

    /**
     * Returns the first interval run time strictly after `afterTime` that falls in the
     * configuration's allowed hours and weekdays.
     *
     * Run times sit on a fixed grid of `Schedule_Interval_Minutes__c` minutes counted from
     * the Unix epoch, so they never drift no matter how late a job fires. For an interval
     * that divides an hour (5, 10, 15, 20, 30, 60) the grid lines up with the clock, e.g.
     * 15 gives :00, :15, :30 and :45.
     *
     * Hours and weekdays are read in the running user's time zone, which is the same time
     * zone Salesforce uses to interpret the cron expression. A blank Schedule_HourOfDay__c
     * or Schedule_DayOfWeek__c means no limit.
     *
     * @throws IntervalScheduleException
     *      If the interval is missing or invalid, or if the hour and weekday limits leave no
     *      run time within the next week.
     */
    public static DateTime getNextIntervalRunTime( Mass_Action_Configuration__c config, DateTime afterTime ) {

        Long intervalMillis = getIntervalMinutes( config ) * 60L * 1000L;

        Set<Integer> allowedHours = parseHours( config.Schedule_HourOfDay__c );
        Set<Integer> allowedWeekdays = parseWeekdays( config.Schedule_DayOfWeek__c );

        Long candidateMillis = ( ( afterTime.getTime() / intervalMillis ) + 1 ) * intervalMillis;

        for ( Integer i = 0; i < INTERVAL_MAX_SEARCH_STEPS; i++ ) {

            DateTime candidate = DateTime.newInstance( candidateMillis );

            Boolean hourAllowed = ( allowedHours.isEmpty() || allowedHours.contains( candidate.hour() ) );
            Boolean weekdayAllowed = ( allowedWeekdays.isEmpty() || allowedWeekdays.contains( getWeekdayIndex( candidate.date() ) ) );

            if ( hourAllowed && weekdayAllowed ) {
                return candidate;
            }

            // The whole hour is excluded, so jump to the first grid slot in the next hour.
            DateTime nextHour = DateTime.newInstance( candidate.date(), Time.newInstance( candidate.hour(), 0, 0, 0 ) ).addHours( 1 );
            candidateMillis = ceilToGrid( nextHour.getTime(), intervalMillis );

        }

        throw new IntervalScheduleException(
            'No run time found within the next week for Repeat Every ' + config.Schedule_Interval_Minutes__c +
            ' Minutes with hours "' + config.Schedule_HourOfDay__c + '" and weekdays "' + config.Schedule_DayOfWeek__c + '".'
        );

    }

    /**
     * Cron expression that fires exactly once, at the given time in the running user's time zone.
     */
    public static String buildOneTimeCron( DateTime runTime ) {
        return String.format(
            '0 {0} {1} {2} {3} ? {4}',
            new String[] {
                String.valueOf( runTime.minute() ),
                String.valueOf( runTime.hour() ),
                String.valueOf( runTime.day() ),
                String.valueOf( runTime.month() ),
                String.valueOf( runTime.year() )
            }
        );
    }

    private static Integer getIntervalMinutes( Mass_Action_Configuration__c config ) {

        Integer minutes = null;

        if ( String.isNotBlank( config.Schedule_Interval_Minutes__c ) && config.Schedule_Interval_Minutes__c.trim().isNumeric() ) {
            minutes = Integer.valueOf( config.Schedule_Interval_Minutes__c.trim() );
        }

        if ( minutes == null || minutes < INTERVAL_MIN_MINUTES || minutes > INTERVAL_MAX_MINUTES || Math.mod( minutes, INTERVAL_STEP_MINUTES ) != 0 ) {
            throw new IntervalScheduleException(
                'Repeat Every (Minutes) must be a multiple of ' + INTERVAL_STEP_MINUTES + ' between ' +
                INTERVAL_MIN_MINUTES + ' and ' + INTERVAL_MAX_MINUTES + ', but was "' + config.Schedule_Interval_Minutes__c + '".'
            );
        }

        return minutes;
    }

    private static Set<Integer> parseHours( String hoursCsv ) {

        Set<Integer> hours = new Set<Integer>();

        if ( String.isBlank( hoursCsv ) || hoursCsv.trim() == '*' ) {
            return hours;
        }

        for ( String token : hoursCsv.split( ',' ) ) {
            if ( token.trim().isNumeric() ) {
                hours.add( Integer.valueOf( token.trim() ) );
            }
        }

        return hours;
    }

    private static Set<Integer> parseWeekdays( String weekdaysCsv ) {

        Set<Integer> weekdays = new Set<Integer>();

        if ( String.isBlank( weekdaysCsv ) || weekdaysCsv.trim() == '?' || weekdaysCsv.trim() == '*' ) {
            return weekdays;
        }

        for ( String token : weekdaysCsv.split( ',' ) ) {
            Integer index = WEEKDAY_TOKENS.indexOf( token.trim().toUpperCase() );
            if ( index >= 0 ) {
                weekdays.add( index );
            }
        }

        return weekdays;
    }

    // 0 = Sunday ... 6 = Saturday
    private static Integer getWeekdayIndex( Date d ) {
        return Math.mod( KNOWN_SUNDAY.daysBetween( d ), 7 );
    }

    private static Long ceilToGrid( Long millis, Long intervalMillis ) {
        return ( ( millis + intervalMillis - 1 ) / intervalMillis ) * intervalMillis;
    }

    // ------------------------------------------------------------------------

    public class IntervalScheduleException extends Exception {}

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