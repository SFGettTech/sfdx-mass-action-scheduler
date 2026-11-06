/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-08-03
 * Description:  Salesforce API version uplift, 54.0 -> 67.0.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Replaced URL.getSalesforceBaseUrl(), removed
 *     |            |              | after API 58.0, with URL.getOrgDomainUrl().
 * 1.0 | 2026-08-07 | Josh Gettman | Added WITH SYSTEM_MODE to restore the
 *     |            |              | system-mode SOQL default lost at API 67.0.
 * ---------------------------------------------------------------------------
 */
public with sharing class LC_URLController {

    @AuraEnabled
    public static Map<String, String> getUrlInfo() {

        String namespace = getNamespaceOfClass( 'LC_URLController' );
        String orgDomainURL = URL.getOrgDomainUrl().toExternalForm();

        // URL.getSalesforceBaseUrl() was removed after API 58.0; URL.getOrgDomainUrl()
        // is its replacement. The 'salesforceBaseURL' key is retained so the shape of
        // this @AuraEnabled response does not change for any consumer, but it now
        // returns the same value as 'orgDomainURL'.
        String salesforceBaseURL = orgDomainURL;

        Map<String, String> result = new Map<String, String>();

        result.put( 'orgDomainURL', orgDomainURL );
        result.put( 'salesforceBaseURL', salesforceBaseURL );
        result.put( 'namespace', namespace );

        return result;
    }

    private static String getNamespaceOfClass( String className ) {

        String namespace = [ SELECT NamespacePrefix FROM ApexClass WHERE Name = :className WITH SYSTEM_MODE LIMIT 1 ].NamespacePrefix;

        return ( String.isBlank( namespace ) ? '' : namespace );
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