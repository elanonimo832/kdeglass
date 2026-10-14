#!/usr/bin/env bash
# Arnés mínimo de pruebas, sin dependencias externas.
#   ejecutar.sh            -> todas
#   ejecutar.sh tokens     -> solo prueba-tokens.sh
: "${PROY:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${PASAN:=0}"; : "${FALLAN:=0}"
FALLOS_F="${TMPDIR:-/tmp}/pruebas-fallos.$$"

rojo()  { printf '\033[1;31m%s\033[0m' "$1"; }
verde() { printf '\033[1;32m%s\033[0m' "$1"; }

ok()    { PASAN=$((PASAN+1)); printf '    %s %s\n' "$(verde OK)" "$1"; }
fallo() { FALLAN=$((FALLAN+1)); printf '%s\n' "${PRUEBA:-?}: $1" >> "$FALLOS_F"
          printf '    %s %s\n' "$(rojo FALLA)" "$1"; }

afirmar() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fallo "$d"; fi; }
negar()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fallo "$d"; else ok "$d"; fi; }
afirmar_igual() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else fallo "$1: esperado '$2', obtenido '$3'"; fi; }
afirmar_existe() { if [ -e "$2" ]; then ok "$1"; else fallo "$1: no existe $2"; fi; }
afirmar_contiene() { if grep -qE "$3" "$2" 2>/dev/null; then ok "$1"; else fallo "$1: '$3' no esta en $(basename "$2")"; fi; }
# Como afirmar_contiene pero IGNORANDO los comentarios. Imprescindible: un patron
# puede aparecer en un comentario que explica el codigo, y entonces la prueba pasa
# aunque el codigo no lo haga. Lo descubrimos con una prueba negativa: quitamos la
# llamada de cadena y la prueba seguia en verde por el comentario que la menciona.
afirmar_codigo() { # afirmar_codigo <desc> <fichero> <patron>
  if grep -vE '^\s*(//|\*|/\*)' "$2" 2>/dev/null | grep -qE "$3"; then ok "$1"
  else fallo "$1: '$3' no esta en el CODIGO de $(basename "$2") (solo en comentarios?)"; fi
}

# Como afirmar_contiene pero con busqueda LITERAL (grep -F). Necesario cuando el
# patron lleva caracteres de regex: 'effects->paintWindow' tiene '->' y el '-' se
# interpretaba como operador, dando un falso fallo.
afirmar_literal() { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else fallo "$1: '$3' no esta en $(basename "$2")"; fi; }
