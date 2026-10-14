#!/usr/bin/env bash
# Takes the two captures simulate.py needs, in ONE command, and restores the effect afterwards.
#
#   ./capture-pair.sh
#
# simulate.py needs the window's title strip with the effect OFF (that is the theme's own
# drawing, which is what the effect samples) and the SAME region of the desktop with the window
# out of the way (that is the backdrop it captures). Getting those by hand is three tools and a
# guess about the rectangle; this reads the rectangle from the effect's own journal, takes both,
# crops both to it, and puts the effect back even if you interrupt it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID=macosglass2
SALIDA="${1:-/tmp}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

efecto() { # efecto on|off
    timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects."$1"Effect "$ID" >/dev/null 2>&1
}

restaurar() {
    efecto loadEffect
    echo
    echo "the effect is loaded again."
}
trap restaurar EXIT INT TERM

# THE RECTANGLE, from the effect's own diagnostics: it prints frame= and barHeight= for the first
# few windows it sees, and that is the same rectangle its band covers. Read with the effect ON,
# before anything is unloaded.
diag=$(timeout 20 journalctl --user --since '60 min ago' -o cat 2>/dev/null \
       | grep 'frame=' | grep 'barHeight=' | grep -v systemd-run | tail -1)
if [ -z "$diag" ]; then
    echo "No 'frame= ... barHeight= ...' line in the journal from the last hour."
    echo "That line comes from the effect itself, so:"
    echo "  1. make sure the effect is loaded and a decorated window is on screen"
    echo "  2. move that window a little, so it repaints"
    echo "  3. run this again"
    exit 2
fi
echo "the effect says:"
echo "  $diag"
# QRect(QPoint(x, y), QSize(w, h)) -> the four numbers, in the order Qt streams them
nums=$(printf '%s' "$diag" | grep -oE 'frame= *QRect\([^)]*\)' | grep -oE '[-0-9]+' | head -4)
bar=$(printf '%s' "$diag" | grep -oE 'barHeight= *[0-9]+' | grep -oE '[0-9]+' | head -1)
set -- $nums
X=${1:-}; Y=${2:-}; ANCHO=${3:-}; ALTO=${4:-}
if [ -z "${X:-}" ] || [ -z "${Y:-}" ] || [ -z "${ANCHO:-}" ] || [ -z "${ALTO:-}" ] || [ -z "${bar:-}" ]; then
    echo "could not read x, y, width, height and barHeight out of that line"
    exit 2
fi
echo "  -> crop x=$X y=$Y w=$ANCHO title bar=${bar}px"

echo
echo "1/3 unloading the effect, so the capture shows the THEME, not the glass..."
efecto unloadEffect
sleep 2
if ! timeout 20 spectacle -b -n -o "$SALIDA/_par_titulo.png" >/dev/null 2>&1; then
    echo "spectacle could not capture the screen"
    exit 1
fi

echo
echo "2/3 MOVE THE WINDOW AWAY from x=$X..$((X+ANCHO)), y=$Y..$((Y+ALTO))"
echo "    (any direction is fine, as long as that region shows the desktop)"
read -r -p "    then press Enter... " _

if ! timeout 20 spectacle -b -n -o "$SALIDA/_par_fondo.png" >/dev/null 2>&1; then
    echo "spectacle could not capture the screen"
    exit 1
fi

echo
echo "3/3 cropping both to the same rectangle..."
python3 - "$SALIDA" "$X" "$Y" "$ANCHO" "$ALTO" "$bar" <<'PYEOF'
import sys
from PIL import Image
salida, x, y, w, h, bar = sys.argv[1], *(int(v) for v in sys.argv[2:7])
recorte = (x, y, x + w, y + bar)          # the title strip only: that is the band
for origen, destino in (("_par_titulo.png", "titulo.png"), ("_par_fondo.png", "fondo.png")):
    im = Image.open(f"{salida}/{origen}").convert("RGB")
    im.crop(recorte).save(f"{salida}/{destino}")
    print(f"  {salida}/{destino}  {im.crop(recorte).size[0]}x{im.crop(recorte).size[1]}")
PYEOF

echo
echo "Now, with the effect loaded again:"
echo "  python3 $HERE/simulate.py --window $SALIDA/titulo.png --backdrop $SALIDA/fondo.png --out $SALIDA/banda.png"
