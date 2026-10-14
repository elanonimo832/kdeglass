# Los scripts del efecto: pocos, claros, autosuficientes y sin el id que rompia el render.
EF="$PROY/effect-kwin"

echo "  -- solo los scripts esenciales --"
# Nine debug scripts were scaffolding for the bisection; their value (the variant
# table) is in INCIDENT.md. FIVE remain, each with a purpose that is still true:
#   build.sh            builds and verifies the paint chain
#   install.sh          installs and activates (needs sudo)
#   verify-chain.sh     the check that prevents the black screen
#   test-glass.sh       live test: the band follows the background
#   test-titlebar.sh    live test: the title bar only, read from KWin's geometry
# The four that were retired to tests/archive/ had stopped being able to say anything:
# test-installed.sh looked for M1.1's flat marker, test-hot.sh and calibrate.sh waited
# for CALIB lines the effect no longer emits, and test-diffusion.sh measured M1.2's band
# diffusion, which the design no longer claims. A live script whose verdict is
# meaningless is worse than no script: it teaches the reader to ignore verdicts.
esperados="build.sh install.sh test-titlebar.sh test-glass.sh verify-chain.sh"
for s in $esperados; do afirmar_existe "existe $s" "$EF/$s"; done

n=$(ls "$EF"/*.sh 2>/dev/null | wc -l)
afirmar_igual "number of scripts (no scaffolding)" "5" "$n"
sobran=""
for x in "$EF"/*.sh; do
  [ -f "$x" ] || continue
  b="$(basename "$x")"
  case " $esperados " in *" $b "*) ;; *) sobran="$sobran $b";; esac
done
afirmar_igual "no sobra ningun script" "" "$sobran"

echo "  -- ningun script carga el id que rompia el render --"
malos=0
for s in "$EF"/*.sh; do
  [ -f "$s" ] || continue
  if grep -nE '(load|unload)Effect[^a-zA-Z0-9]*macosglass([^0-9]|$)' "$s" >/dev/null 2>&1; then
    malos=$((malos+1)); printf '      -> %s usa el id viejo\n' "$(basename "$s")"
  fi
done
afirmar_igual "ningun script carga el id viejo" "0" "$malos"

echo "  -- la comprobacion de la cadena antes de instalar --"
# Sin ella, instalar el .so deja la pantalla negra. Se admite comprobarla
# directamente o delegar en verify-chain.sh (delegar es mejor: una sola fuente).
for s in build.sh install.sh; do
  if grep -qE 'EffectsHandler::paintWindow|verify-chain\.sh' "$EF/$s" 2>/dev/null; then
    ok "$s comprueba la cadena antes de instalar"
  else
    fallo "$s NO comprueba la cadena antes de instalar"
  fi
done

echo "  -- el patron de grep es determinista --"
# grep -q aborta al encontrar la coincidencia y cierra el pipe; con pipefail el
# resultado VARIA y puede abortar la instalacion de un .so correcto. Paso dos veces.
malos=0
for s in "$EF"/*.sh; do
  [ -f "$s" ] || continue
  if grep -nE 'objdump.*\|[[:space:]]*grep[[:space:]]+-q' "$s" >/dev/null 2>&1; then
    malos=$((malos+1)); printf '      -> %s usa grep -q en un pipe\n' "$(basename "$s")"
  fi
done
afirmar_igual "ningun script usa 'grep -q' en un pipe" "0" "$malos"

echo "  -- autosuficiencia: sin binarios de build/ --"
# build/ es regenerable y se borra al recompilar. Un script que llama a
# build/verificar-carga se rompe en cuanto se limpia. (Paso de verdad.)
malos=0
for s in "$EF"/*.sh; do
  [ -f "$s" ] || continue
  if awk '/\$AQUI\/build\// && !/\.so/ {found=1} END{exit !found}' "$s" 2>/dev/null; then
    malos=$((malos+1)); printf '      -> %s llama a un binario de build/\n' "$(basename "$s")"
  fi
done
afirmar_igual "ningun script depende de binarios de build/" "0" "$malos"

echo "  -- ningun script vivo busca una etiqueta de log que ya no existe --"
# The rot this catches: test-hot.sh and calibrate.sh waited for `CALIB` lines that the
# effect stopped emitting when M1.1's coordinate calibration was replaced, and nothing
# noticed for days -- a live script that cannot say anything looks exactly like a live
# script that has nothing to say. Both are in tests/archive/ now.
#
# The rule is narrow ON PURPOSE, and the first version was too wide: it took any ALL-CAPS
# word in single quotes, which matched a heredoc tag in build.sh and the words FOUND and NOT
# in verify-chain.sh, none of which are journal tags. What makes a word a tag is the LINE it
# is used in -- so only lines that actually read the journal count. It needs no allow-list,
# and a check with no allow-list is one nobody will quietly weaken.
faltan=""
for s in "$EF"/*.sh; do
  [ -f "$s" ] || continue
  b="$(basename "$s")"
  etiquetas=$(grep -E 'journalctl' "$s" 2>/dev/null | grep -oE "'[^']*'" \
              | grep -oE '\b[A-Z][A-Z0-9_]{2,}\b' | sort -u)
  for e in $etiquetas; do
    if ! codigo_contiene "$EF/src/glass.cpp" "$e"; then
      faltan="$faltan $b:$e"
    fi
  done
done
afirmar_igual "every journal tag a live script waits for still exists" "" "${faltan# }"
