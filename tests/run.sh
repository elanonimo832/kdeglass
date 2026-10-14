#!/usr/bin/env bash
# Run the tests. Usage: run.sh [name]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
FILTER="${1:-}"
export PROJECT

PASSED=0 FAILED=0

# One temporary directory for the whole run. Counters and failure lists of the
# individual test files live here, so a run writes nothing inside the repository
# (tests/.pass-count is the one deliberate exception) and an interrupted run
# leaves no debris outside $TMPDIR.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/kdeglass-tests.XXXXXX")"
FAILURES_FILE="$TMPD/failures"; : > "$FAILURES_FILE"
trap 'rm -rf "${TMPD:?}"' EXIT

# A file that hangs must not become "the run did not finish": truncated output
# with no summary is exactly how the last two failures hid. Each file is bounded
# and a timeout is reported as a failure of THAT file. Override: TEST_TIMEOUT=0
# disables it (0 means no limit to `timeout`).
TIME_LIMIT="${TEST_TIMEOUT:-120}"

# The pass count is written to tests/.pass-count at the end, as a convenience only (read
# it without re-running the suite). It takes part in NO assertion: a number that watches
# itself oscillates, measured (110 -> 109 -> 110). Nothing reads it, and a cache nobody
# reads cannot contaminate the run that writes it.
#
# Every test file runs in its OWN process (run-one.sh), so a variable, a function, a `set`
# flag or an `exit` in one file cannot reach the next.
for f in "$HERE"/test-*.sh; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .sh)"; name="${name#test-}"
  [ -n "$FILTER" ] && [ "$FILTER" != "$name" ] && continue
  printf '\n\033[1;34m== %s ==\033[0m\n' "$name"
  countFile="$TMPD/$name.count"
  failures="$TMPD/$name.failures"; : > "$failures"
  COUNT_FILE="$countFile" TEST_NAME="$name" FAILURES_FILE="$failures" PASSED=0 FAILED=0 \
    timeout -k 5 "$TIME_LIMIT" bash "$HERE/run-one.sh" "$f"
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf '    \033[1;31m%s\033[0m %s\n' "FAIL" "TIMED OUT after ${TIME_LIMIT}s: the rest of the file was not run"
    printf '%s: TIMED OUT after %ss; the rest of the file was not run (rc=%s)\n' \
      "$name" "$TIME_LIMIT" "$rc" >> "$failures"
    FAILED=$((FAILED + 1))
  elif [ ! -s "$countFile" ]; then
    printf '    \033[1;31m%s\033[0m %s\n' "FAIL" "the process died without reporting a counter (rc=$rc)"
    printf '%s: the test process died without reporting a counter (rc=%s)\n' "$name" "$rc" >> "$failures"
    FAILED=$((FAILED + 1))
  elif [ ! -s "$countFile.done" ]; then
    # The counter file exists, so the EXIT trap ran -- but the file never reached its last
    # line. Without this, a file that dies halfway is indistinguishable from one that
    # finished: it reports the checks it managed to run and nothing fails.
    printf '    \033[1;31m%s\033[0m %s\n' "FAIL" "the file did not reach its end (rc=$rc): its remaining checks were NOT run"
    printf '%s: the file did not reach its end (rc=%s); its remaining checks were NOT run\n' "$name" "$rc" >> "$failures"
    FAILED=$((FAILED + 1))
  fi
  # Partial counts are kept even after a timeout: a file that timed out halfway
  # still passed everything it asserted before that, and hiding those passes
  # would make the total depend on where it hung.
  if [ -s "$countFile" ]; then
    read -r p f_all < "$countFile"
    PASSED=$((PASSED + p)); FAILED=$((FAILED + f_all))
  fi
  [ -s "$failures" ] && cat "$failures" >> "$FAILURES_FILE"
done

printf '\n\033[1m%s\033[0m\n' "-----------------------------"
if [ "$FAILED" -gt 0 ]; then
  printf '  pass: %s   fail: \033[1;31m%s\033[0m\n' "$PASSED" "$FAILED"
  printf '\n  failures:\n'
  [ -f "$FAILURES_FILE" ] && sed 's/^/    - /' "$FAILURES_FILE"
  printf '%s' "$PASSED" > "$HERE/.pass-count"
  exit 1
fi
printf '  pass: \033[1;32m%s\033[0m   fail: 0\n' "$PASSED"
printf '  \033[1;32mALL PASS\033[0m\n'
printf '%s' "$PASSED" > "$HERE/.pass-count"
