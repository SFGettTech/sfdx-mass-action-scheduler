<!-- PROJECT LOGO -->
<p align="center">
  <img src="images/mas-logo.png" alt="Mass Action Scheduler Logo" border="0" />
  <br />
  Declaratively schedule process automation from reports and list views.
</p>

# Mass Action Scheduler — un-namespaced fork

This repository is an **un-namespaced source fork** of Doug Ayers'
[sfdx-mass-action-scheduler](https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler),
maintained internally to **replace the managed Mass Action Scheduler package**.

It is deployed from source rather than installed as a package, and carries no namespace
prefix. There are no org-specific names, ids, endpoints, or credentials anywhere in this
repository — the same source is intended to be **deployed into multiple orgs**. Everything
org-specific (the Named Credential, Auth. Provider, Connected App, and the configuration
records themselves) is created per org at deploy time.

---

## Why this fork exists

The managed package invokes every non-Apex target through the **Salesforce REST Actions
API**, calling back into the same org through a Named Credential. That REST loopback is the
problem.

A Flow invoked that way runs *inside an inbound API call that originated from an outbound
callout*. Salesforce does not permit a callout from that context, so a target Flow could not
perform HTTP callouts of its own. Any Flow needing to call an external service simply could
not be used as a Mass Action target.

Because the package is managed, that behaviour could not be changed in place. This
un-namespaced fork exists so the Flow invocation path can be replaced with an
**in-transaction** invocation, which lifts the restriction.

---

## What is different from upstream

Everything not listed here is upstream behaviour, unchanged.

### 1. Flow targets run in-transaction

`MA_MassActionUtils.invokeTargetAction` routes `Target_Type__c == 'Flow'` to
`toolMassActionFlowInvoker`, which runs the flow through
`Invocable.Action.createCustomAction( 'flow', <name> )` — one flow interview per target row,
in the batch job's own transaction. **Target flows can now make their own HTTP callouts.**

`Workflow`, `QuickAction`, `EmailAlert`, and `Apex` targets are untouched and still go
through the REST Actions API via the configured Named Credential.

Every row is attempted even if an earlier row fails, and a failure raises a single exception
naming the flow and listing every failed row with its inputs, so one bad record cannot
silently mask the rest of the batch.

### 2. Static (hard-coded) field mappings

A target action or flow input can be assigned a **literal value** with no corresponding
source field. `Mass_Action_Mapping__c` gains:

| Field | Purpose |
|---|---|
| `Mapping_Type__c` | `Source Field` (default) or `Static Value` |
| `Source_Value__c` | The literal, used when `Mapping_Type__c` is `Static Value` |

`Source_Field_Name__c` changed from required to optional; requiredness is now enforced
conditionally in the config-builder UI and in Apex. A required target field is satisfied by
**either** a chosen source field **or** a non-blank static value.

Mappings created before this change have a blank `Mapping_Type__c`, which is treated
everywhere as `Source Field`, so **existing configurations behave exactly as before**.

`Source_Value__c` is a text field and its literal is passed through exactly as entered. No
type coercion is performed, so a target input typed as Number, Boolean, or Date may reject
it.

### 3. Migration tooling — not yet built

> **This does not exist yet.** There is no automated tool in this repository for migrating
> configuration records from the managed `dca_mass_action` package to this fork. Cutover is
> currently a manual re-creation of `Mass_Action_Configuration__c` and
> `Mass_Action_Mapping__c` records in the target org.
>
> The inherited `MA_InstallHandler`, `MA_UpgradePageLayoutsService`,
> `MA_SetConfigUniqueNameBatchable`, and `MA_UpgradeMassActionLogsBatchable` classes are
> **upstream package-version upgrade helpers**, not migration tooling. They upgrade data
> between versions of the managed package and are effectively dormant in a source
> deployment, which never runs an install handler.

---

## Behaviour changes to know before you deploy

**A Flow target now runs as the batch job's running user, not as the Named Credential
identity.** This is the most important consequence of running in-transaction. If a Flow
relied on the Named Credential user's permissions, record access, or sharing, it will behave
differently. Review Flow targets for anything that assumed the integration user.

**A Flow target now shares the batch transaction's governor limits.** A flow that performs a
callout consumes a callout from the enclosing transaction, and its DML and SOQL count against
the batch execution's limits rather than a separate API request's.

**The Named Credential is still required — but not for everything.** It is used at batch
runtime by:

- SOQL sources (`MA_SoqlSourceIterable`)
- List View sources (`MA_ListViewSourceBatchable`)
- Anonymous Apex targets, via the SOAP API
- `Workflow`, `QuickAction`, `EmailAlert`, and invocable `Apex` targets, via the REST Actions
  API

It is **no longer used by Flow targets**, and it is **not used by the config-builder UI**. A
configuration whose source is a Report or Apex and whose target is a Flow no longer needs it
at runtime at all.

**The config-builder UI discovers actions as the running user, not through the Named
Credential.** `MA_EditConfigRestController` performs action and action-input discovery
against `MA_MassActionUtils.REST_API_SERVICES_URL` — the org's own domain URL — authorising
with `UserInfo.getSessionId()`. Those requests are routed through the `LC_API` Visualforce
bridge because Lightning session ids are not API-enabled. The admin building a configuration
therefore needs API access and permission to see the target actions; the Named Credential is
not involved in discovery.

**`Invocable.Action` requires a modern API version.** The project note is that
`Invocable.Action` requires **API 56.0 or later**. *(Experimental: the exact minimum has not
been verified against Salesforce documentation. It is moot in practice — this project targets
API 67.0, above any candidate floor, and the in-transaction flow invocation is covered by the
test suite.)*

**API version.** The whole project is on **API 67.0**. Do not bulk-bump API versions as part
of unrelated work; that was done once in a dedicated step.

---

## Requirements

- A Salesforce org on an API version supporting **67.0**.
- Salesforce CLI (`sf`, v2).
- For SOQL sources, List View sources, and non-Flow targets: a Named Credential, Auth.
  Provider, and Connected App in the target org. The **Authentication Setup Wizard** tab
  bundled with this app creates them for you.

---

## Deploying to a target org

The same source deploys to any org. Substitute your own alias for `<target-org>`.

```bash
# 1. deploy the source
sf project deploy start --source-dir force-app --target-org <target-org>

# 2. grant access
sf org assign permset --name Mass_Action_Admin --target-org <target-org>

# 3. create the Named Credential, Auth. Provider, and Connected App
#    open the "Authentication Setup Wizard" tab in the target org and run it,
#    or create the three components manually
```

For a scratch org, `./scripts/create-scratch-org.sh [alias]` does all of the above and seeds
the Account that the report tests require.

### Running the tests

```bash
sf apex run test --target-org <target-org> --code-coverage --result-format human \
  --suite-names Mass_Action_Scheduler_Test_Suite --wait 30
```

The report tests additionally require an Account named `dca_mass_action: MA Test Account` to
exist in the target org, because they run with `SeeAllData = true` against a packaged report.

---

## Cutover from the managed package

Generic outline. Adapt per org, and read the migration-tooling note above first.

1. **Inventory** the existing `dca_mass_action__Mass_Action_Configuration__c` records in the
   target org, with their field mappings and schedules.
2. **Deactivate** the managed package's scheduled jobs so both copies cannot run the same
   automation concurrently.
3. **Deploy this source** to the target org and assign `Mass_Action_Admin`.
4. **Create** the Named Credential, Auth. Provider, and Connected App via the setup wizard.
5. **Re-create** each configuration and its field mappings in the un-namespaced objects.
   This is manual today. Watch for Flow targets that relied on the Named Credential identity
   — they now run as the batch job's running user.
6. **Verify** one configuration end to end with `Active__c = false`, running it on demand
   before scheduling it.
7. **Activate** the new schedules, then **uninstall** the managed package once the fork has
   run cleanly for a full cycle.

Keep the managed package installed but idle until cutover is confirmed. Uninstalling it
deletes its configuration records.

---

## Development

Conventions for this repository — naming, file headers, Apex standards, permission-set and
layout requirements, and the test-suite rules — are documented in [CLAUDE.md](CLAUDE.md).

Branch off `develop` for feature work and open pull requests back to `develop`.

---

## Attribution and license

Mass Action Scheduler is a
[free-as-in-speech](https://www.howtogeek.com/howto/31717/what-do-the-phrases-free-speech-vs.-free-beer-really-mean/)
and [open source](https://opensource.com/resources/what-open-source) passion project
developed by [Doug Ayers](https://douglascayers.com). This fork exists only because of his
work, and remains his code with local modifications layered on top.

- Upstream project:
  [sfdx-mass-action-scheduler/sfdx-mass-action-scheduler](https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler)
- Upstream documentation:
  [project wiki](https://github.com/sfdx-mass-action-scheduler/sfdx-mass-action-scheduler/wiki)

The source code is licensed under the [BSD 3-Clause License](LICENSE), copyright (c)
2017-2023 Doug Ayers, douglascayers.com. Files inherited from upstream retain Doug's header
and the BSD 3-Clause notice; local modifications are recorded in a Modification Log beneath
his header. Some files carry third-party attribution instead — for example `MA_ReportService`
is Salesforce.org (CampaignTools) code under its own notice. Existing attribution is never
removed.

### Acknowledgements

[Appiphony](http://www.lightningstrike.io) for the Strike Wizard component based on the
Lightning Design System [Path blueprint](https://www.lightningdesignsystem.com/components/path/).

[Salesforce Foundation](https://github.com/SalesforceFoundation/CampaignTools) for tools to
query the Salesforce Reports API in Apex.

[Shinichi Tomita](https://twitter.com/stomita) for [jsforce](https://jsforce.github.io/) and
[soql-parse](https://github.com/stomita/soql-parse).

[jQuery](https://jquery.com/) for the jQuery library.

[Aaron Hardy](https://twitter.com/aaronius) for [Penpal](https://github.com/Aaronius/penpal),
a promise-based library for securely communicating with iframes via postMessage.

Third-party library licenses are in [licenses/](licenses/).
