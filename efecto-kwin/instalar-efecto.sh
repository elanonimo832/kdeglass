#!/usr/bin/env bash
# Instala y activa el efecto KWin del proyecto. Necesita sudo. SIN sudo delante.
#
# Autosuficiente: no depende de binarios en build/ (que es regenerable).
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SO="$AQUI/build/plugins/kwin/effects/macosglass2.so"
ID=macosglass2
DEST=/usr/lib/qt6/plugins/kwin/effects/plugins

[ -f "$SO" ] || { echo "Falta el .so. Compila primero:  ./construir.sh"; exit 1; }

# 1. La cadena de pintado: sin ella KWin no dibuja NINGUNA ventana (pantalla negra).
if ! "$AQUI/verificar-cadena.sh" >/dev/null 2>&1; then
  echo "ABORTADO: el .so no continua la cadena de pintado -> pantalla negra."
  echo "Detalle:  ./verificar-cadena.sh"
  exit 1
fi
echo "1. Cadena de pintado: OK"

# 2. Instalar en la ruta que KWin LEE. PluginEffectLoader busca en
#    "kwin/effects/plugins"; un nivel mas arriba KWin no lo ve, y en silencio.
echo "2. Instalando $ID en $DEST"
sudo install -Dm755 "$SO" "$DEST/$ID.so"

# 3. Restos de intentos anteriores. El id 'macosglass' rompia el render, y los
#    plugins de prueba de la biseccion ya no hacen falta.
echo "3. Quitando restos (ids viejos y plugins de prueba)"
for viejo in macosglass libmacosglass bisect testglass2; do
  sudo rm -f "$DEST/$viejo.so" 2>/dev/null || true
  kwriteconfig6 --file kwinrc --group Plugins --key "${viejo}Enabled" --delete 2>/dev/null || true
done
sudo rm -f /usr/share/kwin/effects/macosglass/metadata.json 2>/dev/null || true
sudo rmdir /usr/share/kwin/effects/macosglass 2>/dev/null || true

echo "4. Activando en kwinrc"
kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" true

echo
echo "Instalado y activado."
echo
echo "  Comprobar sin cerrar sesion (carga, mide y descarga solo):"
echo "      ./probar-ya-instalado.sh"
echo
echo "  Para que quede cargado de forma permanente, CIERRA SESION."
echo "  NUNCA uses 'kwin_wayland --replace': en Wayland arranca un segundo"
echo "  compositor que compite por el DRM/GL y deja la pantalla NEGRA."
echo "  Ver INCIDENTE.md."
