#!/usr/bin/env bash
# LIVE test of the ALREADY INSTALLED effect. Installs nothing (does not need sudo).
# Loads, measures and ALWAYS unloads (trap EXIT).
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
ID=macosglass2
SAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build/variantes"; mkdir -p "$SAL"

descargar() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$ID" >/dev/null 2>&1; }
trap 'descargar' EXIT INT TERM

medir() {
  local f="$SAL/instalado-$1.png"; rm -f "$f"
  timeout 25 spectacle -b -n -o "$f" >/dev/null 2>&1 || true
  python3 - "$f" "$1" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB"); px=list(im.getdata()); n=len(px)
    negro=sum(1 for r,g,b in px if r<8 and g<8 and b<8)
    print(f"    {sys.argv[2]:14s} black={100*negro/n:5.1f}%")
except Exception as e:
    print(f"    {sys.argv[2]}: could not measure ({e})")
PY
}

echo "Effect: $ID (already installed). Nothing is installed."
medir control
echo "Loading $ID ..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$ID" >/dev/null 2>&1
sleep 5; medir cargado
echo "Unloading..."; descargar; sleep 3; medir tras-descargar
python3 - "$SAL/instalado-cargado.png" <<'PY'
import sys
from PIL import Image
try:
    im=Image.open(sys.argv[1]).convert("RGB"); px=list(im.getdata()); n=len(px)
    negro=100*sum(1 for r,g,b in px if r<8 and g<8 and b<8)/n
    print(); print("VERDICT:", "BREAKS rendering" if negro>90 else f"does NOT break it (black={negro:.1f}%) -> THE EFFECT WORKS")
except Exception as e: print("could not measure:", e)
PY
