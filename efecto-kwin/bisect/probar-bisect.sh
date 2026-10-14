#!/usr/bin/env bash
# BISECCION: carga el efecto MINIMO (sin paintWindow) en el KWin vivo y mide.
# Sirve para saber si la pantalla negra la causa CUALQUIER efecto nuestro o
# algo especifico de macosglass.
#
# Descarga SIEMPRE al salir (trap EXIT). Si algo fuera mal: bash ~/RECUPERAR-KDE.sh reanimar
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
SAL="$AQUI/build/prueba"; mkdir -p "$SAL"

descargar() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect bisect >/dev/null 2>&1; }
trap descargar EXIT INT TERM

medir() {
  local f="$SAL/$1.png"; rm -f "$f"
  timeout 25 spectacle -b -n -o "$f" >/dev/null 2>&1 || true
  python3 - "$f" "$1" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB")
    px = list(im.getdata()); n = len(px)
    negro = sum(1 for r,g,b in px if r<8 and g<8 and b<8)
    print(f"    {sys.argv[2]:18s} negro={100*negro/n:5.1f}%")
except Exception as e:
    print(f"    {sys.argv[2]}: no se pudo medir ({e})")
PY
}

echo "1. CONTROL (sin bisect cargado)"; medir control
echo "2. Cargando el efecto MINIMO (sin paintWindow)..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect bisect >/dev/null 2>&1
sleep 5; medir bisect-cargado
echo "3. Descargando..."; descargar; sleep 3; medir tras-descargar
echo
echo "Capturas en $SAL"
