#!/usr/bin/env bash
# Prueba EN VIVO una variante concreta de macosglass. Instala, carga, mide y
# DESCARGA SIEMPRE (trap EXIT). Restaura la build buena al salir.
# Uso: ./probar-variante.sh /tmp/macosglass-B-SIN-propiedades.so
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
DEST=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
SAL="$AQUI/build/variantes"; mkdir -p "$SAL"

VAR="${1:-}"
[ -f "$VAR" ] || { echo "Uso: $0 <ruta.so>"; exit 1; }
N="$(basename "$VAR" .so)"

descargar() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass >/dev/null 2>&1; }
trap 'descargar' EXIT INT TERM

medir() {
  local f="$SAL/$N-$1.png"; rm -f "$f"
  timeout 25 spectacle -b -n -o "$f" >/dev/null 2>&1 || true
  python3 - "$f" "$1" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.getdata()); n = len(px)
    negro = sum(1 for r,g,b in px if r<8 and g<8 and b<8)
    print(f"    {sys.argv[2]:14s} negro={100*negro/n:5.1f}%")
except Exception as e:
    print(f"    {sys.argv[2]}: error {e}")
PY
}

echo "Variante: $N"
kwriteconfig6 --file kwinrc --group Plugins --key macosglassEnabled false
sudo install -Dm755 "$VAR" "$DEST" || { echo "fallo la instalacion"; exit 1; }
sleep 1
medir control
echo "Cargando..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect macosglass >/dev/null 2>&1
sleep 5; medir cargado
echo "Descargando..."; descargar; sleep 3; medir tras-descargar

python3 - "$SAL/$N-cargado.png" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB"); px=list(im.getdata()); n=len(px)
    negro = 100*sum(1 for r,g,b in px if r<8 and g<8 and b<8)/n
    print()
    print("VEREDICTO:", "ROMPE el render" if negro>90 else f"NO lo rompe (negro={negro:.1f}%)")
except Exception as e:
    print("no se pudo medir:", e)
PY
