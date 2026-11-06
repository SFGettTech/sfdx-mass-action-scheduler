/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-10-12
 * Description:  Coverage for interval ("Repeat Every X Minutes") scheduling.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-10-12 | Josh Gettman | Added interval run time, one-time cron,
 *     |            |              | validation and scheduling tests.
 * ---------------------------------------------------------------------------
 */
@IsTest
private class MA_MassActionScheduleUtilsTest {

    // 2026-10-12 is a Monday. Built in the running user's time zone, which is the
    // time zone the interval hour and weekday limits are evaluated in.
    private static final DateTime MONDAY_10_07 = DateTime.newInstance( 2026, 10, 12, 10, 7, 30 );

    private static Mass_Action_Configuration__c buildIntervalConfig( String intervalMinutes, String hours, String weekdays ) {
        return new Mass_Action_Configuration__c(
            Name = 'Test Interval Config',
            DeveloperName__c = 'Test_Interval_Config',
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Active__c = false,
            Batch_Size__c = 1,
            Source_Type__c = 'SOQL',
            Source_SOQL_Query__c = 'SELECT Id FROM Account LIMIT 1',
            Target_Type__c = 'Workflow',
            Target_SObject_Type__c = 'Account',
            Schedule_Frequency__c = MA_MassActionScheduleUtils.FREQUENCY_INTERVAL,
            Schedule_Interval_Minutes__c = intervalMinutes,
            Schedule_HourOfDay__c = hours,
            Schedule_DayOfWeek__c = weekdays
        );
    }

    @IsTest
    static void test_next_interval_run_is_next_grid_slot() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '15', null, null );
        Long intervalMillis = 15 * 60 * 1000L;

        DateTime nextRun = MA_MassActionScheduleUtils.getNextIntervalRunTime( config, MONDAY_10_07 );

        System.assert( nextRun > MONDAY_10_07, 'next run must be after the given time' );
        System.assert( nextRun.getTime() - MONDAY_10_07.getTime() <= intervalMillis, 'next run must be within one interval' );
        System.assertEquals( 0, Math.mod( nextRun.getTime(), intervalMillis ), 'next run must sit on the interval grid' );
        System.assertEquals( 10, nextRun.hour() );
        System.assertEquals( 15, nextRun.minute() );

    }

    @IsTest
    static void test_next_interval_run_never_returns_the_given_time() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '15', null, null );

        DateTime onTheGrid = DateTime.newInstance( 2026, 10, 12, 10, 15, 0 );
        DateTime nextRun = MA_MassActionScheduleUtils.getNextIntervalRunTime( config, onTheGrid );

        System.assertEquals( DateTime.newInstance( 2026, 10, 12, 10, 30, 0 ), nextRun );

    }

    @IsTest
    static void test_next_interval_run_respects_hours() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '15', '9', null );

        DateTime nextRun = MA_MassActionScheduleUtils.getNextIntervalRunTime( config, MONDAY_10_07 );

        System.assertEquals( DateTime.newInstance( 2026, 10, 13, 9, 0, 0 ), nextRun, 'past 9 AM today, so the next run is 9:00 tomorrow' );

    }

    @IsTest
    static void test_next_interval_run_respects_weekdays() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '15', null, 'WED' );

        DateTime nextRun = MA_MassActionScheduleUtils.getNextIntervalRunTime( config, MONDAY_10_07 );

        System.assertEquals( DateTime.newInstance( 2026, 10, 14, 0, 0, 0 ), nextRun, 'first run on Wednesday is at midnight' );

    }

    @IsTest
    static void test_next_interval_run_respects_hours_and_weekdays() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '30', '9,10', 'SAT,SUN' );

        DateTime nextRun = MA_MassActionScheduleUtils.getNextIntervalRunTime( config, MONDAY_10_07 );

        System.assertEquals( DateTime.newInstance( 2026, 10, 17, 9, 0, 0 ), nextRun, 'first allowed slot is Saturday 9:00' );

    }

    @IsTest
    static void test_next_interval_run_unreachable_limits_throw() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '15', '25', null );

        try {
            MA_MassActionScheduleUtils.getNextIntervalRunTime( config, MONDAY_10_07 );
            System.assert( false, 'expected IntervalScheduleException' );
        } catch ( MA_MassActionScheduleUtils.IntervalScheduleException e ) {
            System.assert( e.getMessage().contains( 'No run time found' ), e.getMessage() );
        }

    }

    @IsTest
    static void test_invalid_interval_minutes_throw() {

        for ( String badValue : new List<String>{ null, '', '0', '7', '65', 'abc' } ) {

            Mass_Action_Configuration__c config = buildIntervalConfig( badValue, null, null );

            try {
                MA_MassActionScheduleUtils.getNextIntervalRunTime( config, MONDAY_10_07 );
                System.assert( false, 'expected IntervalScheduleException for "' + badValue + '"' );
            } catch ( MA_MassActionScheduleUtils.IntervalScheduleException e ) {
                System.assert( e.getMessage().contains( 'Repeat Every (Minutes)' ), e.getMessage() );
            }

        }

    }

    @IsTest
    static void test_build_one_time_cron() {

        String cron = MA_MassActionScheduleUtils.buildOneTimeCron( DateTime.newInstance( 2026, 10, 12, 14, 45, 0 ) );

        System.assertEquals( '0 45 14 12 10 ? 2026', cron );

    }

    @IsTest
    static void test_schedule_interval_job() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '15', null, null );
        insert config;

        DateTime beforeScheduling = DateTime.now();

        Test.startTest();

        MA_MassActionScheduleUtils.scheduleMassActions( new List<ID>{ config.Id } );

        Test.stopTest();

        CronTrigger ct = [ SELECT Id, CronExpression, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name = :( 'MA_MassAction_' + config.Id ) ];

        System.assert( ct.CronExpression.endsWith( String.valueOf( ct.NextFireTime.year() ) ), 'interval job must be a one-time cron: ' + ct.CronExpression );
        System.assert( ct.NextFireTime > beforeScheduling, 'next fire time must be in the future' );
        System.assert( ct.NextFireTime.getTime() - beforeScheduling.getTime() <= ( 15 * 60 * 1000L ) + 10000L, 'next fire time must be within one interval' );

    }

    @IsTest
    static void test_trigger_schedules_and_reschedules_interval_config() {

        Mass_Action_Configuration__c config = buildIntervalConfig( '15', null, null );
        config.Active__c = true;

        insert config;

        String jobName = 'MA_MassAction_' + config.Id;

        System.assertEquals( 1, [ SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :jobName ], 'activating an interval config schedules it' );

        config.Schedule_Interval_Minutes__c = '30';
        update config;

        System.assertEquals( 1, [ SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :jobName ], 'changing the interval reschedules, not duplicates' );

        config.Active__c = false;
        update config;

        System.assertEquals( 0, [ SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :jobName ], 'deactivating unschedules' );

    }

    @IsTest
    static void test_schedule_jobs() {

        Mass_Action_Configuration__c configA = new Mass_Action_Configuration__c(
            Name = 'Test Config A',
            DeveloperName__c = 'Test_Config_A',
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Active__c = false,
            Batch_Size__c = 200,
            Source_Type__c = 'SOQL',
            Source_List_View_ID__c = 'SELECT Id FROM Account LIMIT 1',
            Target_Type__c = 'Workflow',
            Target_Action_Name__c = null,
            Target_SObject_Type__c = 'Account',
            Schedule_Frequency__c = 'Scheduled',
            Schedule_SecondOfMinute__c = '0',
            Schedule_MinuteOfHour__c = '0',
            Schedule_HourOfDay__c = '1',
            Schedule_DayOfMonth__c = '*',
            Schedule_MonthOfYear__c = '*',
            Schedule_DayOfWeek__c = '?'
        );

        Mass_Action_Configuration__c configB = new Mass_Action_Configuration__c(
            Name = 'Test Config B',
            DeveloperName__c = 'Test_Config_B',
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Active__c = false,
            Batch_Size__c = 200,
            Source_Type__c = 'SOQL',
            Source_List_View_ID__c = 'SELECT Id FROM Account LIMIT 1',
            Target_Type__c = 'Workflow',
            Target_Action_Name__c = null,
            Target_SObject_Type__c = 'Account',
            Schedule_Frequency__c = 'Custom',
            Schedule_Cron__c = '0 0 1 * * ?'
        );

        insert configA;
        insert configB;

        System.assertEquals( 0, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configA.Id) ] );
        System.assertEquals( 0, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configB.Id) ] );

        Test.startTest();

        MA_MassActionScheduleUtils.scheduleMassActions( new List<ID>{ configA.Id, configB.Id } );

        Test.stopTest();

        System.debug( [ SELECT Id, Name FROM CronJobDetail ] );
        System.assertEquals( 1, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configA.Id) ] );
        System.assertEquals( 1, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configB.Id) ] );

        CronTrigger triggerA = [ SELECT Id, CronJobDetail.Name, CronExpression FROM CronTrigger WHERE CronJobDetail.Name LIKE :('%' + configA.Id) ];
        System.assertEquals( MA_MassActionScheduleUtils.buildCron( configA ), triggerA.CronExpression );

        CronTrigger triggerB = [ SELECT Id, CronJobDetail.Name, CronExpression FROM CronTrigger WHERE CronJobDetail.Name LIKE :('%' + configB.Id) ];
        System.assertEquals( configB.Schedule_Cron__c, triggerB.CronExpression );

    }

    @IsTest
    static void test_unschedule_jobs() {

        Mass_Action_Configuration__c configA = new Mass_Action_Configuration__c(
            Name = 'Test Config A',
            DeveloperName__c = 'Test_Config_A',
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Active__c = false,
            Batch_Size__c = 200,
            Source_Type__c = 'SOQL',
            Source_List_View_ID__c = 'SELECT Id FROM Account LIMIT 1',
            Target_Type__c = 'Workflow',
            Target_Action_Name__c = null,
            Target_SObject_Type__c = 'Account',
            Schedule_Frequency__c = 'Scheduled',
            Schedule_SecondOfMinute__c = '0',
            Schedule_MinuteOfHour__c = '0',
            Schedule_HourOfDay__c = '1',
            Schedule_DayOfMonth__c = '*',
            Schedule_MonthOfYear__c = '*',
            Schedule_DayOfWeek__c = '?'
        );

        Mass_Action_Configuration__c configB = new Mass_Action_Configuration__c(
            Name = 'Test Config B',
            DeveloperName__c = 'Test_Config_B',
            Named_Credential__c = 'Mass_Action_Test_Named_Credential',
            Active__c = false,
            Batch_Size__c = 200,
            Source_Type__c = 'SOQL',
            Source_List_View_ID__c = 'SELECT Id FROM Account LIMIT 1',
            Target_Type__c = 'Workflow',
            Target_Action_Name__c = null,
            Target_SObject_Type__c = 'Account',
            Schedule_Frequency__c = 'Custom',
            Schedule_Cron__c = '0 0 1 * * ?'
        );

        insert configA;
        insert configB;

        MA_MassActionScheduleUtils.scheduleMassActions( new List<ID>{ configA.Id, configB.Id } );

        System.assertEquals( 1, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configA.Id) ] );
        System.assertEquals( 1, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configB.Id) ] );

        Test.startTest();

        MA_MassActionScheduleUtils.unscheduleMassActions( new List<ID>{ configA.Id, configB.Id } );

        Test.stopTest();

        System.debug( [ SELECT Id, Name FROM CronJobDetail ] );
        System.assertEquals( 0, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configA.Id) ] );
        System.assertEquals( 0, [ SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :('%' + configB.Id) ] );

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