# CLAUDE.md

Project conventions for this repository. Follow these in every task unless the user
overrides them for a specific piece of work.

---

## 1. What this repo is

An **un-namespaced fork** of Doug Ayers' archived
[sfdx-mass-action-scheduler](https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler),
maintained internally by Gett Tech.

**Why the fork exists:** it replaces the *managed* Mass Action Scheduler package. Because
the managed package's namespace and packaging constraints prevented target Flows from
issuing their own HTTP callouts, this source-deployed, namespace-free copy is used instead,
so scheduled Flow targets can make their own HTTP callouts.

Practical consequences to keep in mind:

- `sfdx-project.json` sets `"namespace": ""` — there is no namespace prefix. Do not
  reintroduce one, and do not assume `MA_NamespaceUtils.NAMESPACE` is non-empty
  (`force-app/main/default/classes/MA_NamespaceUtils.cls` resolves it at runtime; here it
  resolves to `''`).
- Source is **deployed/pushed**, not installed as a package. Install-handler code
  (`MA_InstallHandler`) is inherited from upstream and is effectively dormant.
- `upstream` remote still points at the archived original. `origin` is
  `SFGettTech/sfdx-mass-action-scheduler`. Default working branch is `develop`.

### Name collisions while the managed package is still installed

A namespace isolates *API names*, so the fork's `Mass_Action_Configuration__c` and the
managed `dca_mass_action__Mass_Action_Configuration__c` coexist happily. It does **not**
isolate every name. Some metadata carries a separate, org-wide unique display name, and for
those the fork collides with the managed package head-on.

**`CustomNotificationType.customNotifTypeName` is not namespace-isolated.** Deploying the
fork alongside the managed package fails with:

> `duplicate value found: CustomNotifTypeName duplicates value on Mass Action Notification`

`force-app/main/default/notificationtypes/Mass_Action_Notification.notiftype-meta.xml`
therefore uses a distinct display name:

```xml
<customNotifTypeName>Mass Action Notification (Unpackaged)</customNotifTypeName>
<masterLabel>Mass Action Notification (Unpackaged)</masterLabel>
```

The **API name `Mass_Action_Notification` and the file name are deliberately unchanged.**
`flows/MAS_Mass_Action_Configuration.flow-meta.xml` references the notification type by API
name in four places, and `manifest/package.xml` lists it by API name. Renaming the file or
the API name would break the flow; renaming only the display value does not.

Once the managed package is uninstalled from an org, the display name may optionally be
changed back to `Mass Action Notification` in a follow-up deploy. That is cosmetic and is
not required for anything to work.

When adding metadata, watch for other types with an org-wide unique display name and give
the unpackaged copy a distinct one the same way.

### Repo layout (verified)

```
force-app/main/default/
  applications/  aura/  classes/  contentassets/  flexipages/  flows/
  layouts/  namedCredentials/  notificationtypes/  objects/  pages/
  permissionsets/  quickActions/  reports/  staticresources/  tabs/
  testSuites/  triggers/
config/project-scratch-def.json     manifest/package.xml
scripts/create-scratch-org.sh       scripts/recreate-manifest.sh
.github/workflows/main.yml          licenses/   images/   _layouts/
```

- Apex API version: **67.0** (`sourceApiVersion` in `sfdx-project.json`; `MA_MassActionUtils`
  hardcodes `/services/data/v67.0` and `/services/Soap/s/67.0`).
- UI today is **Aura**, not LWC (`force-app/main/default/aura/`, e.g. `MA_EditConfigCmp`,
  `MA_RunConfigCmp`). There is no `lwc/` folder yet — `.forceignore` already anticipates
  one (jsconfig, eslintrc, `__tests__`). The LWC rules below apply when LWC is introduced.
- Visualforce: `pages/LC_APIPage.page`, `LC_VisualforceDomainPage.page`,
  `MA_SetupAuthWizardPage.page`.
- Custom objects: `Mass_Action_Configuration__c`, `Mass_Action_Log__c`,
  `Mass_Action_Mapping__c`, plus platform events `Mass_Action_Job_Change_Event__e` and
  `Mass_Action_Batch_Apex_Status_Event__e`.
- There is **no `package.json`** at the root — no npm/jest/eslint/prettier tooling is
  configured locally. Do not add one without being asked.

---

## 2. Naming

| Thing | Convention |
|---|---|
| New Apex class | Prefix `tool` — e.g. `toolCalloutService` |
| New test class | `<ClassName>TEST` — e.g. `toolCalloutServiceTEST` |
| Inherited upstream classes | Keep existing `MA_` / `LC_` prefixes — do **not** rename |
| Inherited upstream tests | Keep existing `...Test` suffix — do **not** rename |

There are currently **no** `tool`-prefixed classes; every class in `classes/` is upstream
(`MA_*`, `LC_*`). The `tool` prefix is what distinguishes our code from Doug's.

Register new test classes in the test suite — see §6.

---

## 3. File headers

**Every** Apex class/trigger, LWC JS/HTML/XML, and Visualforce file begins with a header
block containing:

- **Author** — Josh Gettman
- **Date** — creation date
- **Description** — what the file does
- **Version** — bumped **only after deployment**, never as part of an edit
- **Modification Log** — table with columns `Ver | Date | Author | Modification`

### Version rule

Do not bump `Version` when writing or editing code. The bump happens *after* the change is
deployed. When making a change, add a Modification Log row describing it; leave the version
number alone unless the user says the change has been deployed.

### Comment syntax per file type

**Apex (`.cls`, `.trigger`)** — block comment at the very top:

```apex
/**
 * Author:       Josh Gettman
 * Date:         2026-08-03
 * Description:  Executes outbound HTTP callouts for scheduled Mass Action targets.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Initial creation.
 * ---------------------------------------------------------------------------
 */
public with sharing class toolCalloutService {
```

**Visualforce (`.page`, `.component`)** — HTML/XML comment before the root tag:

```html
<!--
    Author:       Josh Gettman
    ...
-->
<apex:page ...>
```

**LWC HTML (`.html`)** — `<!-- ... -->` comment, placed inside/around the template per
LWC's requirement that the template root be `<template>`.

**LWC JS (`.js`)** — the file must **not** start with a comment. Imports come first, then
the header block, immediately above the class/export declaration:

```js
import { LightningElement, api } from 'lwc';
import getConfig from '@salesforce/apex/toolConfigService.getConfig';

/**
 * Author:       Josh Gettman
 * ...
 */
export default class ToolConfigPanel extends LightningElement {
```

**`-meta.xml` files** — must **not** start with a comment. The `<?xml version="1.0" ... ?>`
declaration is line 1 (the XML spec forbids anything — including whitespace or comments —
before the declaration); the XML comment header goes immediately after it, before the root
element:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
    Author:       Josh Gettman
    ...
-->
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
```

**These placements are settled — not Experimental.** Do not re-litigate them.

### Separator lines in XML/HTML comment headers

In `.cmp`, `.page`, `.component`, LWC `.html`, and `-meta.xml` headers, the Modification
Log separator must **not** be a run of hyphens. The XML spec forbids `--` inside a comment,
and the Metadata API rejects the component outright:

> `ParseError ... Message: The string "--" is not permitted within comments.`

Use `=` for the separator in XML/HTML comments:

```html
<!--
    Modification Log:
    =======================================================================
    Ver | Date       | Author       | Modification
    =======================================================================
    1.0 | 2026-08-03 | Josh Gettman | Initial creation.
    =======================================================================
-->
```

Apex (`.cls`, `.trigger`) and JS block comments are unaffected — keep using `-` there.

### Attribution: new files vs. modified upstream files

| File | Header |
|---|---|
| **New `tool*` file** (original work) | My standard header block **only**. Do **not** add the BSD-3 block, and do not add Doug's header. |
| **Modified upstream file** (`MA_*`, `LC_*`) | Keep Doug's top header **and** the trailing BSD-3 block; insert my Modification Log beneath his header. |

New original work is ours and carries no upstream license text. Adding BSD-3 to a file
Doug never wrote misattributes it.

For **modified** upstream source files, preserve Doug Ayers' existing header **and** the
full BSD 3-Clause block. In upstream `.cls` files these appear as:

- top of file: `/** Author: Doug Ayers / Website / GitHub / License: BSD 3-Clause License */`
- bottom of file (after the closing brace): the complete BSD 3-Clause license text

Leave both in place, verbatim. Add our Modification Log **beneath Doug's header**, e.g.:

```apex
/**
 * Author: Doug Ayers
 * Website: https://douglascayers.com
 * GitHub: https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler
 * License: BSD 3-Clause License
 */
/**
 * Modified by:  Josh Gettman
 * Date:         2026-08-03
 * Description:  Allow Flow targets to perform their own HTTP callouts.
 * Version:      1.0
 *
 * Modification Log:
 * ---------------------------------------------------------------------------
 * Ver | Date       | Author       | Modification
 * ---------------------------------------------------------------------------
 * 1.0 | 2026-08-03 | Josh Gettman | Removed post-callout DML from target invoke.
 * ---------------------------------------------------------------------------
 */
```

Never strip, relicense, or reword Doug's attribution. The root `LICENSE` and
`licenses/*.txt` (appiphony, jquery, jsforce, penpal, sfdc-lax, soql-parser) stay as-is.

A few upstream files carry *third-party* attribution instead of Doug's — e.g.
`MA_ReportService` / `MA_ReportServiceTest` are Salesforce.org (CampaignTools) code under
their own BSD-style notice. Preserve whatever notice a file already has; the rule is
"never remove existing attribution," not "always Doug."

---

## 4. Apex standards

### Sharing
- `with sharing` by default on every new class.
- Use `without sharing` / `inherited sharing` **only** when system mode is genuinely
  required, and document why in a comment above the class (upstream does this — see
  `MA_NamespaceUtils`, which explains the install-handler constraint).

### String literals
- **Single quotes** for all Apex string literals and for string replacements
  (`String.replace`, `String.format` arguments, etc.).

### Bulkification
- **No SOQL inside loops.** Query once, collect into maps/sets.
- **No DML inside loops.** Accumulate into a `List<SObject>` and do one DML per operation.
- **No DML after a callout** in the same transaction. If a callout must be followed by
  persistence, split it — queueable/platform-event/async continuation — never
  callout-then-DML in one context.

### SOQL construction
- **Never** put `:var IS NOT NULL`-style bind checks inside a SOQL string.
- Do null/blank/empty checks in Apex *before* building the query, and only append the
  relevant filter clauses when the value is actually populated:

```apex
String soql = 'SELECT Id FROM Account';
List<String> filters = new List<String>();
if ( String.isNotBlank( accountName ) ) {
    filters.add( 'Name = :accountName' );
}
if ( !filters.isEmpty() ) {
    soql += ' WHERE ' + String.join( filters, ' AND ' );
}
```

### DML and error handling
- Use `Database.insert` / `Database.update` / `Database.delete` with **`allOrNone = false`**,
  then aggregate errors manually from the `Database.SaveResult[]` / `UpsertResult[]` /
  `DeleteResult[]` and surface them.
- **Verbose error messages on every failure path.** Include the record Id, the field, the
  status code, and the operation context — enough to diagnose without a debug log.
- **Typed exceptions are rethrown as-is.** Do not catch a typed exception only to wrap it
  in a generic `Exception`/`DmlException` and lose the type. Upstream's `MA_Exceptions`
  (with nested `AnonymousApexException`, `SOQLQueryException`, `InvokeActionException`)
  is the model — extend that pattern rather than inventing parallel hierarchies.

```apex
List<Database.SaveResult> results = Database.insert( records, false );
List<String> errors = new List<String>();
for ( Integer i = 0; i < results.size(); i++ ) {
    if ( !results[i].isSuccess() ) {
        for ( Database.Error err : results[i].getErrors() ) {
            errors.add( String.format(
                'Failed to insert record at index {0} (Id: {1}): [{2}] {3} — fields: {4}',
                new Object[] {
                    i, records[i].Id, err.getStatusCode(), err.getMessage(),
                    String.join( err.getFields(), ', ' )
                }
            ));
        }
    }
}
```

### Testability
- Design for injection: define an **interface** for anything that reaches outside the
  class (HTTP, callouts, scheduling, describe calls, clock), and inject the implementation.
- Expose seams with **`@TestVisible`** (private members, injectable static instances)
  rather than widening real visibility to `public`.
- Reuse the existing mocks where they fit: `MA_HttpCalloutMock`, `MA_AsyncApexJobMock`.

### File organization
- **DTO / wrapper / helper inner classes go at the END of the file**, after the public
  methods (and, for upstream files, before the trailing BSD license block).

---

## 5. New custom fields — permission set and layout are mandatory

A new field is **not done** when the `.field-meta.xml` is written. Every new custom field
must also be:

1. **Granted read/edit in `Mass_Action_Admin`** —
   `force-app/main/default/permissionsets/Mass_Action_Admin.permissionset-meta.xml`
   (78 `<fieldPermissions>` entries today; add yours in the same shape):

   ```xml
   <fieldPermissions>
       <editable>true</editable>
       <field>Mass_Action_Configuration__c.My_New_Field__c</field>
       <readable>true</readable>
   </fieldPermissions>
   ```

   Set `<editable>false</editable>` for formula/rollup/auto-number fields — they are
   read-only and the deploy fails if marked editable.

2. **Added to the relevant page layout** in `force-app/main/default/layouts/`:
   - `Mass_Action_Configuration__c-Mass Action Configuration Layout`
   - `Mass_Action_Log__c-Mass Action Log Layout` / `... Parent Log Layout` / `... Child Log Layout`
   - `Mass_Action_Mapping__c-Mass Action Mapping Layout`

Skipping either step produces FLS failures at runtime — the Aura UI renders blank or
errors, and Apex hits `INSUFFICIENT_ACCESS` / field-not-accessible errors. These are
easy to miss because they don't fail at deploy time.

---

## 6. Tests

### Suite registration is required

CI runs `--suitenames Mass_Action_Scheduler_Test_Suite`. A test class that is not in
`force-app/main/default/testSuites/Mass_Action_Scheduler_Test_Suite.testSuite-meta.xml`
**never runs in CI** — it will silently contribute nothing and its coverage gap won't
surface until a deploy fails.

So, for every new test:

- **Either** add the new class to the suite's `<testClassName>` list (keep the list
  alphabetized, as it is today),
- **or** add the new test methods to an existing class that is already registered.

Never leave a new test class unregistered.

### Seed data

Some tests depend on org data that exists **before** the test run: an Account named
**`dca_mass_action: MA Test Account`**. This is required by the report tests —
`MA_ReportServiceTest` is `@IsTest( SeeAllData = true )` (the packaged test report filters
on that account name), which is also why it can't use `@TestSetup`.

**Reuse the repo's existing seed mechanism; do not invent a new one.** The account is
created outside the tests, by the CLI, in two places that must stay in sync:

- `scripts/create-scratch-org.sh` — for local scratch orgs
- `.github/workflows/main.yml` — for CI (the name is held in the
  `TEST_ACCOUNT_NAME_FOR_APEX_TESTS` secret, because the colon in the name breaks the
  YAML parser)

If a new test needs pre-existing org data, extend those two paths rather than adding a
parallel seeding script, a static resource, or a `@TestSetup` workaround.

For everything that *doesn't* need `SeeAllData`, create data inside the test with
`@TestSetup` as normal — the seed account is an exception forced by the Analytics API,
not the general pattern.

---

## 7. Claim labeling

When stating something about Salesforce behavior, an API, or this codebase:

- **Doc-Verified** — confirmed against official Salesforce documentation (or directly
  read out of this repo). Cite what confirmed it.
- **Experimental** — inferred, remembered, or untested. Label it explicitly so it is
  never mistaken for confirmed behavior.

Anything unlabeled should be something plainly visible in the file under discussion.
When in doubt, label it Experimental.

---

## 8. CLI, build, deploy

### Use `sf` (v2). Do not write new `sfdx force:*` (v7) commands.

Salesforce has retired the legacy `sfdx force:*` command style. **Author all new scripts,
CI steps, and any commands you run in `sf` (v2) syntax.**

The scripts and workflow currently in the repo (`scripts/create-scratch-org.sh`,
`scripts/recreate-manifest.sh`, `.github/workflows/main.yml`) are still on v7 —
`force:org:create`, `force:source:push`, `force:apex:test:run`, and the `npm install
sfdx-cli` step in CI. **These may be modernized to `sf` in the same pass** as any change
that touches them; don't treat them as frozen, and don't copy their style into new work.

```bash
# create + seed a scratch org (alias defaults to mas-scratch)
./scripts/create-scratch-org.sh [alias]

# deploy source
sf project deploy start --source-dir force-app --target-org <alias>

# run the test suite
sf apex run test --target-org <alias> --code-coverage --result-format human \
  --suite-names Mass_Action_Scheduler_Test_Suite --wait 20

# create a scratch org
sf org create scratch --definition-file config/project-scratch-def.json \
  --alias <alias> --duration-days 30 --set-default

# assign the permission set
sf org assign permset --name Mass_Action_Admin --target-org <alias>

# seed the test Account (see §6)
sf data create record --sobject Account \
  --values "Name='dca_mass_action: MA Test Account'" --target-org <alias>

# validate everything in a throwaway scratch org, the way CI does
./scripts/validate-scratch.sh <alias> --target-dev-hub <devhub> [--delete-on-success]

# regenerate manifest/package.xml (see below — do not hand-edit it)
sf project generate manifest --source-dir force-app --output-dir manifest --api-version 67.0
```

### `manifest/package.xml` is generated, never hand-edited

`manifest/package.xml` is a **build artifact generated from `force-app`**. Do not edit it by
hand, and do not add members to it manually.

**Regenerate it whenever components are added, removed, or renamed** — new Apex classes, new
custom fields, new objects, new Aura bundles, anything that changes what lives under
`force-app`:

```bash
sf project generate manifest --source-dir force-app --output-dir manifest --api-version 67.0
```

Keep `--api-version` in step with `sourceApiVersion` in `sfdx-project.json` (currently
**67.0**); the generator does not read it from the project file, so omitting the flag writes
whatever the CLI defaults to.

Two things to know when you regenerate:

- The older `./scripts/recreate-manifest.sh` does the same job the long way, via a legacy v7
  `sfdx force:source:convert` round trip. Prefer the command above.
- Report folders are emitted with a trailing slash, `Mass_Action_Test_Reports/`, where a
  hand-written manifest would say `Mass_Action_Test_Reports`. Both resolve to the same
  metadata; this is a generator formatting difference, not a dropped component. Verify a
  regeneration with `sf project convert source --root-dir force-app --manifest
  manifest/package.xml --output-dir <tmp>` and diff the file listing if in doubt.

Required org setup (both CI and the scratch script do this):

- assign permission set **`Mass_Action_Admin`**
- create an Account named `dca_mass_action: MA Test Account` — the report tests depend on it

CI (`.github/workflows/main.yml`) runs on push/PR to `main` and `develop`: creates a
scratch org, pushes source, assigns the permset, seeds the test Account, runs the Apex test
suite with coverage, collects Flow test coverage, uploads to Codecov, deletes the org.

---

## 9. Branching

- **`develop` is the working branch.** Branch off `develop` for feature work and target
  PRs back at `develop`.
- `main` is downstream of `develop`; don't commit feature work directly to either.
- CI runs on push/PR to both `main` and `develop`.

---

## 10. Working rules

- Don't rename, reformat, or "modernize" upstream `MA_*` / `LC_*` files beyond what the
  task requires — keep diffs against upstream small and reviewable.
- Don't add npm tooling, linters, or formatters unless asked.
- Don't bump `Version` headers as part of an edit (see §3).
- New Apex goes in `force-app/main/default/classes/` with a matching `.cls-meta.xml` at
  API version **67.0** to stay consistent with the project.
- Every new class ships with its `<ClassName>TEST` class, **registered in the test suite** (§6).
- Every new custom field ships with its `Mass_Action_Admin` field permission **and** a
  layout placement (§5).
- New scripts and CI use `sf` (v2), never `sfdx force:*` (§8).
- After adding or removing components, regenerate `manifest/package.xml` rather than
  editing it by hand (§8).
- Branch off `develop` (§9).
- Note the "don't modernize upstream Apex" rule above does **not** apply to the CLI
  scripts and workflow — those may be moved to `sf` in the same pass (§8).
