#!/usr/bin/env bash
# Comprueba la causa raiz de la pantalla negra: MacosGlassEffect::paintWindow()
# TIENE que continuar la cadena de KWin llamando a effects->paintWindow().
#
# EffectsHandler::paintWindow() llama a UN solo efecto; la cadena avanza porque
# Effect::paintWindow() (la base) vuelve a entrar en effects->paintWindow(). Si un
# efecto sobreescribe paintWindow() y no llama a la base, la cadena se corta,
# finalPaintWindow() no se ejecuta y no se dibuja NINGUNA ventana (fondo negro).
#
# NOTA sobre el grep: se usa `grep -c ... >/dev/null` y NO `grep -q`. Con -q, grep
# aborta en cuanto encuentra la coincidencia y cierra el pipe; sumado a `pipefail`
# eso daba un resultado NO DETERMINISTA (a veces pasaba, a veces no). Con -c lee
# toda la entrada y el resultado es estable. Ver INCIDENT.md.
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUENTE="$AQUI/src/glass.cpp"
SO="$AQUI/build/plugins/kwin/effects/macosglass2.so"
SISTEMA=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so

fallo=0

echo "=== 1. La fuente llama a effects->paintWindow() ==="
if grep -cE 'effects->paintWindow\(' "$FUENTE" >/dev/null; then
  echo "  OK: $FUENTE contiene la llamada de cadena"
else
  echo "  FALLO: paintWindow() NO continua la cadena -> pantalla negra"
  fallo=1
fi

echo
echo "=== 2. El binario compilado llama a EffectsHandler::paintWindow ==="
if [ ! -f "$SO" ]; then
  echo "  (aun no compilado; ejecuta: cmake --build build)"
  fallo=1
elif objdump -d --demangle "$SO" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null; then
  echo "  OK: $(basename "$SO") llama a la cadena"
else
  echo "  FALLO: el binario compilado NO llama a la cadena"
  fallo=1
fi

echo
echo "=== 3. El .so instalado en el sistema ==="
if [ ! -f "$SISTEMA" ]; then
  echo "  (no hay .so instalado en $SISTEMA)"
  echo "  Instalalo con:  ./install.sh"
elif objdump -d --demangle "$SISTEMA" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null; then
  echo "  OK: el .so instalado es el ARREGLADO"
else
  echo "  AVISO: el .so instalado NO lleva la cadena. NO lo actives."
  echo "         Reinstala:  ./install.sh"
  fallo=1
fi

echo
if [ "$fallo" -eq 0 ]; then
  echo "CADENA OK: el efecto no puede dejar la pantalla negra por este motivo."
else
  echo "CADENA ROTA: NO actives este efecto hasta arreglarlo."
fi
exit "$fallo"
