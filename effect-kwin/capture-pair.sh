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

# THE RECTANGLE, from the effect's own diagnostics. The format is Qt's, so the four numbers are
# inside `frame= KWin::RectF(1226,476 1387x1138)` -- x, y, then width x height. The first version
# of this expected `QRect(QPoint(...), QSize(...))`, which is NOT what Qt streams for a RectF, and
# the user's run died on it; hence the tolerant extraction and the --geometry mode, which lets the
# suite check this against the exact line their journal produced.
leer_geometria() { # leer_geometria "<journal line>" -> "x y w h bar" or nothing
    local linea="$1" trozo
    # head -1 matters: the line carries frame, client AND expanded rectangles, and all three
    # have numbers. Reading the first is the frame; reading all of them produced three lines.
    trozo=$(printf '%s' "$linea" | grep -oE 'frame= *[A-Za-z:_]*RectF?\([^)]*\)' \
            | grep -oE '\([^)]*\)' | head -1 | tr -d '()')
    [ -n "$trozo" ] || return 1
    local bar
    bar=$(printf '%s' "$linea" | grep -oE 'barHeight= *[0-9]+' | grep -oE '[0-9]+' | head -1)
    # FIVE NUMBERS OUT, not the raw "x,y wxh". The first version of this printed the rectangle as
    # Qt writes it, which LOOKS right and is not usable: the caller does `set -- $leidos` and got
    # "1226,476" for x and nothing at all for the height, so the run died with "could not read x,
    # y, width, height and barHeight" while the --geometry test passed. The test checked the
    # intermediate value; the path that consumed it was what broke.
    local xy wh
    xy=$(printf '%s' "$trozo" | cut -d' ' -f1)
    wh=$(printf '%s' "$trozo" | cut -d' ' -f2)
    printf '%s %s %s %s %s\n' \
        "$(printf '%s' "$xy" | cut -d, -f1)" "$(printf '%s' "$xy" | cut -d, -f2)" \
        "$(printf '%s' "$wh" | cut -dx -f1)" "$(printf '%s' "$wh" | cut -dx -f2)" "$bar"
}

# TEST MODE FIRST, before the trap is armed: this path must not touch the effect at all, and
# with the trap armed its "loaded again" line ended up inside the captured output -- which is how
# the suite noticed that reading a rectangle was reloading the user's effect.
# ONE resolver, used by the test mode AND by the capture path, so that a test of the parse is a
# test of the step the capture actually performs. The version before this tested `leer_geometria`
# while the capture path read a variable named `bar` that no longer existed: the guard saw bar=''
# on every run, and the test could not see it because it never exercised that step.
resolver_geometria() { # <line> -> "x y w h bar", all five or nothing
    local l
    l=$(leer_geometria "$1") || return 1
    set -- $l
    if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ] || [ -z "${5:-}" ]; then
        return 1
    fi
    printf '%s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5"
}

if [ "${1:-}" = "--geometry" ]; then
    resolver_geometria "${2:-}" || { echo "could not read x, y, width, height and barHeight"; exit 2; }
    exit 0
fi

efecto() { # efecto on|off
    timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects."$1"Effect "$ID" >/dev/null 2>&1
}

restaurar() {
    efecto loadEffect
    echo
    echo "the effect is loaded again."
}
trap restaurar EXIT INT TERM


CAPTION="${2:-}"
diag=$(timeout 20 journalctl --user --since '60 min ago' -o cat 2>/dev/null \
       | grep 'title bar band:' | grep -v systemd-run \
       | { if [ -n "$CAPTION" ]; then grep -F "$CAPTION"; else cat; fi; } | tail -1)
if [ -z "$diag" ]; then
    echo "No 'title bar band: ... frame= ... barHeight= ...' line in the journal from the last hour."
    echo "That line comes from the effect itself, so:"
    echo "  1. make sure the effect is loaded and a decorated window is on screen"
    echo "  2. move that window a little, so it repaints"
    if [ -n "$CAPTION" ]; then
        echo "  3. or drop the caption filter '$CAPTION': it may not match any window"
    else
        echo "  3. run this again"
    fi
    exit 2
fi
echo "the effect says:"
echo "  $diag"
ventana=$(printf '%s' "$diag" | sed -n 's/.*title bar band: *"\([^"]*\)".*/\1/p')
echo "  -> that is the window \"$ventana\""

leidos=$(resolver_geometria "$diag") || { echo "could not read the rectangle out of that line"; exit 2; }
set -- $leidos
X=$1; Y=$2; ANCHO=$3; ALTO=$4; bar=$5
if [ -z "${X:-}" ] || [ -z "${Y:-}" ] || [ -z "${ANCHO:-}" ] || [ -z "${ALTO:-}" ] || [ -z "${bar:-}" ]; then
    echo "could not read x, y, width, height and barHeight out of that line"
    echo "  (parsed: x='${X:-}' y='${Y:-}' width='${ANCHO:-}' height='${ALTO:-}' bar='${bar:-}')"
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
