# Los scripts del efecto: pocos, claros, autosuficientes y sin el id que rompia el render.
EF="$PROY/effect-kwin"

echo "  -- solo los scripts esenciales --"
# Nueve scripts de depuracion fueron andamiaje de la biseccion; su valor (la tabla
# de variantes) ya esta en INCIDENT.md. Quedan cuatro con un proposito claro:
#   build.sh          compila y verifica la cadena
#   install.sh    instala y activa (necesita sudo)
#   test-installed.sh prueba en vivo sin sudo (carga, mide, descarga)
#   verify-chain.sh   la comprobacion que evita la pantalla negra
esperados="build.sh install.sh test-installed.sh verify-chain.sh"
for s in $esperados; do afirmar_existe "existe $s" "$EF/$s"; done

n=$(ls "$EF"/*.sh 2>/dev/null | wc -l)
afirmar_igual "numero de scripts (sin andamiaje)" "4" "$n"
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
