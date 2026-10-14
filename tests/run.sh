#!/usr/bin/env bash
# Run the tests. Usage: run.sh [name]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROY="$(cd "$HERE/.." && pwd)"
FILTER="${1:-}"
export PROY

PASAN=0 FALLAN=0

# One temporary directory for the whole run. Counters and failure lists of the
# individual test files live here, so a run writes nothing inside the repository
# (tests/.pass-count is the one deliberate exception) and an interrupted run
# leaves no debris outside $TMPDIR.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/kdeglass-tests.XXXXXX")"
FALLOS_F="$TMPD/failures"; : > "$FALLOS_F"
trap 'rm -rf "${TMPD:?}"' EXIT

# A file that hangs must not become "the run did not finish": truncated output
# with no summary is exactly how the last two failures hid. Each file is bounded
# and a timeout is reported as a failure of THAT file. Override: TEST_TIMEOUT=0
# disables it (0 means no limit to `timeout`).
TIEMPO_LIMITE="${TEST_TIMEOUT:-120}"

# El recuento se guarda en tests/.pass-count al terminar, solo como comodidad
# (leerlo sin releer la salida). NO participa en ninguna asercion: un numero que
# se vigila a si mismo oscila, comprobado (110 -> 109 -> 110). Nada lo lee: un
# cache que nadie lee no puede contaminar la corrida que lo escribe.
#
# Cada fichero de prueba corre en su PROPIO proceso (run-one.sh): asi una variable,
# una funcion, un `set` o un `exit` de un fichero no puede alcanzar al siguiente.
for f in "$HERE"/test-*.sh; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .sh)"; name="${name#test-}"
  [ -n "$FILTER" ] && [ "$FILTER" != "$name" ] && continue
  printf '\n\033[1;34m== %s ==\033[0m\n' "$name"
  cuenta="$TMPD/$name.count"
  fallos="$TMPD/$name.failures"; : > "$fallos"
  CUENTA="$cuenta" PRUEBA="$name" FALLOS_F="$fallos" PASAN=0 FALLAN=0 \
    timeout -k 5 "$TIEMPO_LIMITE" bash "$HERE/run-one.sh" "$f"
  rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    printf '    \033[1;31m%s\033[0m %s\n' "FAIL" "TIMED OUT after ${TIEMPO_LIMITE}s: the rest of the file was not run"
    printf '%s: TIMED OUT after %ss; the rest of the file was not run (rc=%s)\n' \
      "$name" "$TIEMPO_LIMITE" "$rc" >> "$fallos"
    FALLAN=$((FALLAN + 1))
  elif [ ! -s "$cuenta" ]; then
    printf '    \033[1;31m%s\033[0m %s\n' "FAIL" "the process died without reporting a counter (rc=$rc)"
    printf '%s: the test process died without reporting a counter (rc=%s)\n' "$name" "$rc" >> "$fallos"
    FALLAN=$((FALLAN + 1))
  elif [ ! -s "$cuenta.fin" ]; then
    # The counter file exists, so the EXIT trap ran -- but the file never reached its last
    # line. Without this, a file that dies halfway is indistinguishable from one that
    # finished: it reports the checks it managed to run and nothing fails.
    printf '    \033[1;31m%s\033[0m %s\n' "FAIL" "the file did not reach its end (rc=$rc): its remaining checks were NOT run"
    printf '%s: the file did not reach its end (rc=%s); its remaining checks were NOT run\n' "$name" "$rc" >> "$fallos"
    FALLAN=$((FALLAN + 1))
  fi
  # Partial counts are kept even after a timeout: a file that timed out halfway
  # still passed everything it asserted before that, and hiding those passes
  # would make the total depend on where it hung.
  if [ -s "$cuenta" ]; then
    read -r p f_all < "$cuenta"
    PASAN=$((PASAN + p)); FALLAN=$((FALLAN + f_all))
  fi
  [ -s "$fallos" ] && cat "$fallos" >> "$FALLOS_F"
done

printf '\n\033[1m%s\033[0m\n' "-----------------------------"
if [ "$FALLAN" -gt 0 ]; then
  printf '  pass: %s   fail: \033[1;31m%s\033[0m\n' "$PASAN" "$FALLAN"
  printf '\n  failures:\n'
  [ -f "$FALLOS_F" ] && sed 's/^/    - /' "$FALLOS_F"
  printf '%s' "$PASAN" > "$HERE/.pass-count"
  exit 1
fi
printf '  pass: \033[1;32m%s\033[0m   fail: 0\n' "$PASAN"
printf '  \033[1;32mALL PASS\033[0m\n'
printf '%s' "$PASAN" > "$HERE/.pass-count"
