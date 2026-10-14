#!/usr/bin/env bash
# Run the tests. Usage: run.sh [name]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

export PASAN=0 FALLAN=0
: "${FALLOS_F:=/tmp/tests-failures.$$}"

for f in "$HERE"/test-*.sh; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .sh)"; name="${name#test-}"
  [ -n "$FILTER" ] && [ "$FILTER" != "$name" ] && continue
  printf '\n\033[1;34m== %s ==\033[0m\n' "$name"
  PRUEBA="$name" PROY="$(cd "$HERE/.." && pwd)"
  export PRUEBA PROY
  # shellcheck source=/dev/null
  source "$HERE/lib.sh"
  # shellcheck source=/dev/null
  source "$f"
done

printf '\n\033[1m%s\033[0m\n' "-----------------------------"
if [ "$FALLAN" -gt 0 ]; then
  printf '  pass: %s   fail: \033[1;31m%s\033[0m\n' "$PASAN" "$FALLAN"
  printf '\n  failures:\n'
  [ -f "$FALLOS_F" ] && sed 's/^/    - /' "$FALLOS_F"
  rm -f "$FALLOS_F" 2>/dev/null
  exit 1
fi
rm -f "$FALLOS_F" 2>/dev/null
printf '  pass: \033[1;32m%s\033[0m   fail: 0\n' "$PASAN"
printf '  \033[1;32mALL PASS\033[0m\n'
