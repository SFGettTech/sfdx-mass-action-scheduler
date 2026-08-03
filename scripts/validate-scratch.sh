#!/usr/bin/env bash

# =========================================================================== #
# validate-scratch.sh
# -------------------
# Stands up a throwaway scratch org and validates this source in it the same
# way CI does: create, deploy, assign the permission set, ensure the seed
# Account exists, then run the Apex test suite.
#
# USAGE
#   scripts/validate-scratch.sh <org-alias> [options]
#
#   <org-alias>                 Required. Alias for the scratch org to create.
#
#   --target-dev-hub <alias>    Dev Hub to create the scratch org from.
#                               Defaults to the CLI's configured default Dev Hub.
#   --duration-days <n>         Scratch org lifetime. Default 1.
#   --delete-on-success         Delete the scratch org if validation passes.
#                               Off by default; the org is kept so a failure can
#                               be investigated.
#   -h, --help                  Show this help.
#
# EXAMPLES
#   scripts/validate-scratch.sh mas-validate --target-dev-hub my-devhub
#   scripts/validate-scratch.sh mas-validate --delete-on-success
#
# Nothing here is specific to any one org. The alias and Dev Hub are supplied by
# the caller; everything else comes from this repository.
#
# Uses the sf (v2) CLI throughout. Do not reintroduce legacy `sfdx force:*`
# commands, which Salesforce has retired.
#
# TWO PORTABILITY RULES, both learned the hard way on Windows/Git Bash:
#
#   1. Success is read from the CLI's own `--json` "status" field, never from
#      the process exit code. The Windows `sf` launcher delegates to sf.cmd and
#      returns 1 even when a command succeeds, so `set -e` on exit codes aborts
#      a perfectly good run. The JSON status is correct on every platform.
#
#   2. No argument passed to `sf` may contain a space. The same Windows launcher
#      mangles them, failing with "'C:\Program' is not recognized". That is why
#      the seed Account is created by an anonymous Apex file rather than by
#      `sf data create record --values "Name='...'"`.
# =========================================================================== #

set -uo pipefail

# --------------------------------------------------------------------------- #
# Configuration derived from the repository, not from any particular org
# --------------------------------------------------------------------------- #

SCRATCH_DEF="config/project-scratch-def.json"
SOURCE_DIR="force-app"
PERMISSION_SET="Mass_Action_Admin"
TEST_SUITE="Mass_Action_Scheduler_Test_Suite"

# Required by the report tests, which run with SeeAllData=true against a packaged
# report that filters on this Account name. Ported from the seed step in
# scripts/create-scratch-org.sh and .github/workflows/main.yml.
SEED_ACCOUNT_NAME="dca_mass_action: MA Test Account"

SEED_APEX_FILE=".validate-seed.apex"
TEST_RESULT_FILE=".validate-test-results.json"

DURATION_DAYS=1
DEV_HUB=""
DELETE_ON_SUCCESS=false
ORG_ALIAS=""

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

usage() {
  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
}

log()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
fail() { printf '\n\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
  rm -f "$SEED_APEX_FILE"
}
trap cleanup EXIT

# Extracts the CLI's top-level numeric "status" from a --json payload. Nested
# status fields in Salesforce CLI output are strings ("Succeeded"), so the first
# numeric match is the command's own status.
json_status() {
  printf '%s' "${1:-}" \
    | tr -d '\n\r' \
    | grep -o '"status"[[:space:]]*:[[:space:]]*[0-9][0-9]*' \
    | head -1 \
    | grep -o '[0-9][0-9]*$'
}

# Extracts a named scalar from a --json payload: json_field <payload> <name>
json_field() {
  printf '%s' "${1:-}" \
    | tr -d '\n\r' \
    | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}[^,\"}]*\"\{0,1\}" \
    | head -1 \
    | sed 's/.*:[[:space:]]*//; s/^"//; s/"$//'
}

# Runs an sf command with --json, checks the JSON status, and echoes the payload
# on stdout so callers can inspect it. Never trusts the process exit code.
sf_json() {
  local description="$1"; shift
  local payload status
  payload=$( sf "$@" --json 2>/dev/null )
  status=$( json_status "$payload" )

  if [ -z "$payload" ]; then
    printf '\n\033[31mERROR: %s produced no output.\033[0m\n' "$description" >&2
    printf 'Check that the sf (v2) CLI is working: sf version\n' >&2
    return 1
  fi

  if [ "${status:-1}" != "0" ]; then
    printf '\n\033[31mERROR: %s failed.\033[0m\n' "$description" >&2
    printf '%s\n' "$payload" | tr ',' '\n' | grep -i '"message"' | head -5 >&2
    printf '%s' "$payload" > "$TEST_RESULT_FILE"
    printf 'Full CLI response written to %s\n' "$TEST_RESULT_FILE" >&2
    return 1
  fi

  printf '%s' "$payload"
}

# --------------------------------------------------------------------------- #
# Arguments
# --------------------------------------------------------------------------- #

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)            usage; exit 0 ;;
    --target-dev-hub)     [ $# -ge 2 ] || fail "--target-dev-hub requires a value"
                          DEV_HUB="$2"; shift 2 ;;
    --duration-days)      [ $# -ge 2 ] || fail "--duration-days requires a value"
                          DURATION_DAYS="$2"; shift 2 ;;
    --delete-on-success)  DELETE_ON_SUCCESS=true; shift ;;
    -*)                   fail "Unknown option: $1 (try --help)" ;;
    *)                    [ -z "$ORG_ALIAS" ] || fail "Unexpected argument: $1"
                          ORG_ALIAS="$1"; shift ;;
  esac
done

[ -n "$ORG_ALIAS" ] || { usage; fail "An org alias is required."; }

command -v sf >/dev/null 2>&1 || fail "The sf (v2) CLI is not on PATH."
[ -f "$SCRATCH_DEF" ] || fail "Cannot find $SCRATCH_DEF. Run this from the repository root."

case "$PWD" in
  *\ *) fail "The repository path contains a space ($PWD). The sf CLI launcher cannot handle that on Windows; move the checkout somewhere without spaces." ;;
esac

# --------------------------------------------------------------------------- #
# 1. Create the scratch org
# --------------------------------------------------------------------------- #

log "Creating scratch org '$ORG_ALIAS' (${DURATION_DAYS}d) from $SCRATCH_DEF"

create_args=(
  org create scratch
  --definition-file "$SCRATCH_DEF"
  --alias "$ORG_ALIAS"
  --duration-days "$DURATION_DAYS"
  --wait 20
)
[ -n "$DEV_HUB" ] && create_args+=( --target-dev-hub "$DEV_HUB" )

create_out=$( sf_json "Scratch org creation" "${create_args[@]}" ) || exit 1
info "Username: $( json_field "$create_out" username )"

# --------------------------------------------------------------------------- #
# 2. Deploy the source
# --------------------------------------------------------------------------- #

log "Deploying $SOURCE_DIR"

deploy_out=$( sf_json "Deploy" \
  project deploy start \
  --source-dir "$SOURCE_DIR" \
  --target-org "$ORG_ALIAS" \
  --wait 30 ) || {
    printf '\nComponent failures:\n' >&2
    printf '%s' "${deploy_out:-}" | tr ',' '\n' | grep -i '"problem"' | head -20 >&2
    exit 1
  }

info "Deployed components: $( json_field "$deploy_out" numberComponentsDeployed )"

# --------------------------------------------------------------------------- #
# 3. Assign the permission set
# --------------------------------------------------------------------------- #

log "Assigning permission set $PERMISSION_SET"

sf_json "Permission set assignment" \
  org assign permset \
  --name "$PERMISSION_SET" \
  --target-org "$ORG_ALIAS" >/dev/null || exit 1

info "Assigned."

# --------------------------------------------------------------------------- #
# 4. Ensure the seed Account exists, before any test runs
# --------------------------------------------------------------------------- #
# The report tests use SeeAllData=true, so this record must already be committed
# in the org rather than created inside a test.
#
# The upstream seed step is `sfdx force:data:record:create --values "Name='...'"`.
# Ported to sf v2 this would be `sf data create record --values "Name='...'"`,
# but that argument contains spaces, which the Windows sf launcher mangles. Doing
# it in anonymous Apex avoids the space entirely and is better anyway: it is
# idempotent, so re-running against a surviving org cannot create duplicates.

log "Ensuring seed Account exists"
info "$SEED_ACCOUNT_NAME"

cat > "$SEED_APEX_FILE" <<APEX
// Seed data for the Mass Action report tests.
// MA_ReportServiceTest runs with SeeAllData = true against a packaged report
// that filters on this Account name, so the record must exist before the tests
// run and cannot be created inside them.
//
// The marker below is built by concatenation on purpose. The CLI's --json
// response echoes this source alongside the debug log, so a marker written as a
// whole literal would be matched in the source text and always report the first
// branch. Concatenating means the complete marker only ever appears in the log.
String seedName = '${SEED_ACCOUNT_NAME}';
List<Account> existing = [ SELECT Id FROM Account WHERE Name = :seedName LIMIT 1 ];
String seedAction = 'present';
if ( existing.isEmpty() ) {
    insert new Account( Name = seedName );
    seedAction = 'created';
}
System.debug( 'VALIDATE' + '_SEED=' + seedAction );
APEX

seed_out=$( sf_json "Seed Account creation" \
  apex run \
  --file "$SEED_APEX_FILE" \
  --target-org "$ORG_ALIAS" ) || exit 1

seed_action=$( printf '%s' "$seed_out" | grep -o 'VALIDATE_SEED=[a-z]*' | head -1 | sed 's/.*=//' )
case "${seed_action:-}" in
  created) info "Created." ;;
  present) info "Already present; left alone." ;;
  *)       info "Seed step completed, but its outcome could not be read." ;;
esac

# --------------------------------------------------------------------------- #
# 5. Run the test suite, mirroring CI
# --------------------------------------------------------------------------- #

log "Running Apex test suite $TEST_SUITE"

test_out=$( sf apex run test \
  --target-org "$ORG_ALIAS" \
  --suite-names "$TEST_SUITE" \
  --code-coverage \
  --wait 30 \
  --json 2>/dev/null )

printf '%s' "$test_out" > "$TEST_RESULT_FILE"

outcome=$( json_field "$test_out" outcome )
tests_ran=$( json_field "$test_out" testsRan )
failing=$( json_field "$test_out" failing )
pass_rate=$( json_field "$test_out" passRate )
coverage=$( json_field "$test_out" orgWideCoverage )

if [ -z "$outcome" ]; then
  fail "Could not read a test result from the CLI. Raw response saved to $TEST_RESULT_FILE"
fi

info "Outcome:       $outcome"
info "Tests ran:     ${tests_ran:-?}"
info "Failing:       ${failing:-?}"
info "Pass rate:     ${pass_rate:-?}"
info "Org coverage:  ${coverage:-?}"

# --------------------------------------------------------------------------- #
# 6. Report and optionally clean up
# --------------------------------------------------------------------------- #

if [ "$outcome" != "Passed" ]; then
  printf '\n\033[31m==> VALIDATION FAILED\033[0m\n'
  printf '\nFailure messages:\n'
  printf '%s' "$test_out" \
    | tr ',' '\n' \
    | grep -o '"Message"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/"Message"[[:space:]]*:[[:space:]]*//' \
    | head -20
  printf '\nFull results: %s\n' "$TEST_RESULT_FILE"
  echo "The scratch org '$ORG_ALIAS' has been left in place so you can investigate:"
  echo "    sf org open --target-org $ORG_ALIAS"
  echo "Delete it when finished:"
  echo "    sf org delete scratch --target-org $ORG_ALIAS --no-prompt"
  exit 1
fi

rm -f "$TEST_RESULT_FILE"
printf '\n\033[32m==> VALIDATION PASSED\033[0m\n'

if [ "$DELETE_ON_SUCCESS" = true ]; then
  log "Deleting scratch org '$ORG_ALIAS'"
  sf_json "Scratch org deletion" \
    org delete scratch --target-org "$ORG_ALIAS" --no-prompt >/dev/null || exit 1
  info "Deleted."
else
  echo "Scratch org '$ORG_ALIAS' kept. Delete it with:"
  echo "    sf org delete scratch --target-org $ORG_ALIAS --no-prompt"
fi
