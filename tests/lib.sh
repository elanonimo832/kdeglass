#!/usr/bin/env bash
# Minimal test harness. No external dependencies.
#   run.sh            -> all
#   run.sh effect     -> only test-effect.sh
: "${PROY:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${PASAN:=0}"; : "${FALLAN:=0}"
FALLOS_F="${TMPDIR:-/tmp}/tests-failures.$$"

rojo()  { printf '\033[1;31m%s\033[0m' "$1"; }
verde() { printf '\033[1;32m%s\033[0m' "$1"; }

ok()    { PASAN=$((PASAN+1)); printf '    %s %s\n' "$(verde OK)" "$1"; }
fallo() { FALLAN=$((FALLAN+1)); printf '%s\n' "${PRUEBA:-?}: $1" >> "$FALLOS_F"
          printf '    %s %s\n' "$(rojo FAIL)" "$1"; }

afirmar() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fallo "$d"; fi; }
negar()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fallo "$d"; else ok "$d"; fi; }
afirmar_igual() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else fallo "$1: expected '$2', got '$3'"; fi; }
afirmar_existe() { if [ -e "$2" ]; then ok "$1"; else fallo "$1: does not exist: $2"; fi; }
afirmar_contiene() { if grep -qE "$3" "$2" 2>/dev/null; then ok "$1"; else fallo "$1: '$3' not found in $(basename "$2")"; fi; }

# Like afirmar_contiene but IGNORING comments. Essential: a pattern can appear in
# a comment that explains the code, and then the test passes while the code does
# not do it. We learned this the hard way: we removed the paint-chain call and the
# test stayed green because of the comment that mentions it.
afirmar_codigo() { # afirmar_codigo <description> <file> <pattern>
  if grep -vE '^\s*(//|\*|/\*)' "$2" 2>/dev/null | grep -qE "$3"; then ok "$1"
  else fallo "$1: '$3' not found in the CODE of $(basename "$2") (only in comments?)"; fi
}

# Like afirmar_contiene but with LITERAL search (grep -F). Needed when the pattern
# contains regex characters: 'effects->paintWindow' has '->' and the '-' was being
# interpreted as an operator, producing a false failure.
afirmar_literal() { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else fallo "$1: '$3' not found in $(basename "$2")"; fi; }
