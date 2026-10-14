#!/usr/bin/env bash
# Prueba EN VIVO cualquier efecto por su .so y su id. Instala, carga, mide y
# DESCARGA SIEMPRE (trap EXIT).
# Uso: ./probar-generico.sh <ruta.so> <id-del-efecto>
# Ej:  ./probar-generico.sh /tmp/glass2/build/plugins/kwin/effects/testglass2.so testglass2
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
SO="${1:-}"; ID="${2:-}"
[ -f "$SO" ] && [ -n "$ID" ] || { echo "Uso: $0 <ruta.so> <id>"; exit 1; }
DEST=/usr/lib/qt6/plugins/kwin/effects/plugins/$(basename "$SO")
SAL="/home/jracosta/Projects/Deepseek Harness/analisis-kde-macos/efecto-kwin/build/variantes"; mkdir -p "$SAL"

descargar() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$ID" >/dev/null 2>&1; }
trap 'descargar' EXIT INT TERM

medir() {
  local f="$SAL/$ID-$1.png"; rm -f "$f"
  timeout 25 spectacle -b -n -o "$f" >/dev/null 2>&1 || true
  python3 - "$f" "$1" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB"); px=list(im.getdata()); n=len(px)
    negro=sum(1 for r,g,b in px if r<8 and g<8 and b<8)
    print(f"    {sys.argv[2]:14s} negro={100*negro/n:5.1f}%")
except Exception as e:
    print(f"    {sys.argv[2]}: error {e}")
PY
}

echo "Efecto: $ID   (desde $(basename "$SO"))"
kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" false
sudo install -Dm755 "$SO" "$DEST" || { echo "fallo la instalacion"; exit 1; }
sleep 1
medir control
echo "Cargando $ID ..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$ID" >/dev/null 2>&1
sleep 5; medir cargado
echo "Descargando..."; descargar; sleep 3; medir tras-descargar
python3 - "$SAL/$ID-cargado.png" <<'PY'
import sys
from PIL import Image
try:
    im=Image.open(sys.argv[1]).convert("RGB"); px=list(im.getdata()); n=len(px)
    negro=100*sum(1 for r,g,b in px if r<8 and g<8 and b<8)/n
    print(); print("VEREDICTO:", "ROMPE el render" if negro>90 else f"NO lo rompe (negro={negro:.1f}%)")
except Exception as e: print("no se pudo medir:", e)
PY
