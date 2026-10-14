#!/usr/bin/env bash
# Instala el efecto KWin del proyecto (macosglass2). Necesita sudo. SIN sudo delante.
#
# HISTORIA DEL NOMBRE (INCIDENTE.md): el mismo codigo compilado con el id
# `macosglass` dejaba la composicion 100 % negra; con un id nuevo funciona.
# Medido tres veces. Por eso el plugin se llama macosglass2 y este script limpia
# cualquier resto del id viejo.
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SO="$AQUI/build/plugins/kwin/effects/macosglass2.so"
ID=macosglass2
DEST=/usr/lib/qt6/plugins/kwin/effects/plugins

[ -f "$SO" ] || { echo "Falta el .so. Compila:  ./construir.sh"; exit 1; }

# La cadena de pintado es obligatoria: sin ella no se dibuja ninguna ventana.
if ! objdump -d --demangle "$SO" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null; then
  echo "ABORTADO: el .so no llama a effects->paintWindow() -> pantalla negra."
  echo "Ejecuta:  ./verificar-cadena.sh"
  exit 1
fi

echo "1. Instalando $ID en la ruta de KWin..."
sudo install -Dm755 "$SO" "$DEST/$ID.so"

echo "2. Quitando restos de intentos anteriores (ids viejos y plugins de prueba)..."
for viejo in macosglass libmacosglass bisect testglass2; do
  sudo rm -f "$DEST/$viejo.so" 2>/dev/null || true
  kwriteconfig6 --file kwinrc --group Plugins --key "${viejo}Enabled" --delete 2>/dev/null || true
done
sudo rm -f /usr/share/kwin/effects/macosglass/metadata.json 2>/dev/null || true
sudo rmdir /usr/share/kwin/effects/macosglass 2>/dev/null || true

echo "3. Activando $ID..."
kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" true

echo
echo "4. PRUEBA DIRECTA (lo que hace KWin):"
"$AQUI/build/verificar-carga" 2>&1 | grep -vE 'explicitly states' | sed 's/^/   /'

echo
echo "5. Estado en el KWin que corre:"
printf '   isEffectSupported: '; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectSupported $ID 2>&1
printf '   isEffectLoaded   : '; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded $ID 2>&1
echo
echo "   Prueba EN VIVO sin cerrar sesion (carga, mide y descarga solo):"
echo "     ./probar-generico.sh \"$SO\" $ID"
echo
echo "   Para que quede cargado de forma permanente, CIERRA SESION (nunca"
echo "   'kwin_wayland --replace': deja la pantalla negra, ver INCIDENTE.md)."
