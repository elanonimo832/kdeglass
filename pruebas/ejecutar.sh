#!/usr/bin/env bash
# Ejecuta las pruebas. Uso: ejecutar.sh [nombre]
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTRO="${1:-}"

export PASAN=0 FALLAN=0
export FALLOS=""

for f in "$AQUI"/prueba-*.sh; do
  [ -f "$f" ] || continue
  nombre="$(basename "$f" .sh)"; nombre="${nombre#prueba-}"
  [ -n "$FILTRO" ] && [ "$FILTRO" != "$nombre" ] && continue
  printf '\n\033[1;34m== %s ==\033[0m\n' "$nombre"
  PRUEBA="$nombre" PROY="$(cd "$AQUI/.." && pwd)"
  export PRUEBA PROY
  # shellcheck source=/dev/null
  source "$AQUI/lib.sh"
  # shellcheck source=/dev/null
  source "$f"
done

printf '\n\033[1m%s\033[0m\n' "-----------------------------"
if [ "$FALLAN" -gt 0 ]; then
  printf '  pasan: %s   fallan: \033[1;31m%s\033[0m\n' "$PASAN" "$FALLAN"
  printf '\n  fallos:\n'
  [ -f "${FALLOS_F:-/nonexistent}" ] && sed 's/^/    - /' "$FALLOS_F"
  rm -f "$FALLOS_F" 2>/dev/null
  exit 1
fi
rm -f "$FALLOS_F" 2>/dev/null
printf '  pasan: \033[1;32m%s\033[0m   fallan: 0\n' "$PASAN"
printf '  \033[1;32mTODO PASA\033[0m\n'
