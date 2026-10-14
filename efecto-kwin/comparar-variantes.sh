#!/usr/bin/env bash
# BISECCION DECISIVA: compara dos builds de macosglass midiendo el negro en pantalla.
#
# Uso:  ./comparar-variantes.sh /tmp/macosglass-SIN-paintWindow.so
#       ./comparar-variantes.sh /tmp/macosglass-CON-paintWindow.so
#
# Instala la variante, carga el efecto, captura, mide y lo DESCARGA SIEMPRE
# (trap EXIT). Vuelve a dejar instalada la variante CON paintWindow al terminar.
# Si algo fuera mal:  bash ~/RECUPERAR-KDE.sh reanimar
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
DEST=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
SAL="$AQUI/build/comparacion"; mkdir -p "$SAL"

VAR="${1:-}"
[ -f "$VAR" ] || { echo "Uso: $0 <ruta-al-.so>"; echo "Variantes: /tmp/macosglass-SIN-paintWindow.so  /tmp/macosglass-CON-paintWindow.so"; exit 1; }
NOMBRE="$(basename "$VAR" .so)"

descargar() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass >/dev/null 2>&1; }
restaurar() { sudo install -Dm755 "$AQUI/build/plugins/kwin/effects/macosglass.so" "$DEST" 2>/dev/null; }
trap 'descargar; restaurar' EXIT INT TERM

medir() {
  local f="$SAL/$NOMBRE-$1.png"; rm -f "$f"
  timeout 25 spectacle -b -n -o "$f" >/dev/null 2>&1 || true
  python3 - "$f" "$1" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.getdata()); n = len(px)
    negro = sum(1 for r,g,b in px if r<8 and g<8 and b<8)
    print(f"    {sys.argv[2]:16s} negro={100*negro/n:5.1f}%")
except Exception as e:
    print(f"    {sys.argv[2]}: error {e}")
PY
}

echo "Variante bajo prueba: $NOMBRE"
echo "1. Instalando la variante..."
sudo install -Dm755 "$VAR" "$DEST" || { echo "  fallo la instalacion"; exit 1; }
kwriteconfig6 --file kwinrc --group Plugins --key macosglassEnabled false
sleep 1

echo "2. CONTROL (descargado)"; medir control
echo "3. Cargando el efecto..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect macosglass >/dev/null 2>&1
sleep 5; medir cargado
echo "4. Descargando..."; descargar; sleep 3; medir tras-descargar

echo
if [ -f "$SAL/$NOMBRE-cargado.png" ]; then
python3 - "$SAL/$NOMBRE-cargado.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); px=list(im.getdata()); n=len(px)
negro = 100*sum(1 for r,g,b in px if r<8 and g<8 and b<8)/n
print("VEREDICTO:", "EL EFECTO ROMPE EL RENDER (100% negro)" if negro>90 else f"NO lo rompe (negro={negro:.1f}%)")
PY
fi
echo "Capturas en $SAL"
