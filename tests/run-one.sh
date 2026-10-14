#!/usr/bin/env bash
# Run ONE test file, in its OWN process. Invoked by run.sh; not meant to be run
# by hand (use `tests/run.sh <name>`).
#
# Why a process per file: run.sh used to `source` every test file into a single
# shell. A variable, a function or a `set` flag set in one file then reached the
# next -- measured, not theorised: test-offscreen.sh sets HEADER and it was
# still set when test-harness.sh ran (see the canary there). An `exit` anywhere
# also ended the whole suite, which is one way for a run to stop without a
# summary. Isolation is what makes "the failure belongs to this file" true.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${COUNT_FILE:?COUNT_FILE (where to write the counters) is required}"
: "${TEST_NAME:?TEST_NAME (the test name) is required}"
: "${PROJECT:=$(cd "$HERE/.." && pwd)}"
: "${FAILURES_FILE:=${TMPDIR:-/tmp}/tests-failures.$$}"
export PROJECT TEST_NAME FAILURES_FILE

# Written from an EXIT trap so it happens even if the test calls `exit`: a file
# that dies halfway must still contribute the checks it did run, instead of
# disappearing from the totals.
escribir_cuenta() { printf '%s %s\n' "${PASSED:-0}" "${FAILED:-0}" > "$COUNT_FILE"; }
trap escribir_cuenta EXIT

# shellcheck source=/dev/null
source "$HERE/lib.sh"
# shellcheck source=/dev/null
source "$1"

# THE FILE REACHED ITS END, and the counter alone cannot say that. The EXIT trap writes the
# counter even when the file dies halfway, so a file killed by an unbound variable reported
# the checks it had run before dying and the suite called it a pass -- measured, not
# theorised: a new check referenced a variable this file never defines, and `run.sh` printed
# ALL PASS while that check never ran. A check that does not run is not a check, and a suite
# that cannot tell "finished" from "died" cannot say that either.
# A SEPARATE FILE, because the counter is written with `>` from the EXIT trap and would
# overwrite a marker written here.
printf 'DONE\n' > "$COUNT_FILE.done"
