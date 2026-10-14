#!/usr/bin/env bash
# Takes the two captures simulate.py needs, in ONE command, and puts everything back.
#
#   ./capture-pair.sh [output-dir]
#   ./capture-pair.sh --geometry "1226,476,1387,1138,38"     # test mode: parse only, no screen
#
# simulate.py needs the window's title strip with the effect OFF (that is the theme's own
# drawing, which is what the effect samples) and the SAME region of the desktop with the window
# out of the way (that is the backdrop it captures). By hand that is three tools and a guess.
#
# TWO THINGS THIS LEARNED THE HARD WAY, and both are why it looks like this:
#
# 1. The geometry must be FRESH. The first version read the band's rectangle from the effect's own
#    journal, which can be an hour old -- and was: the crop landed on a window that had moved
#    since, so "the theme's strip" was really the desktop, and the simulation still looked
#    convincing. It now asks KWin for the ACTIVE window's geometry at the moment of the capture,
#    the way test-titlebar.sh does.
# 2. The unload must be CHECKED, not assumed. `unloadEffect` can be refused, and a capture taken
#    with the effect still loaded is the effect's OUTPUT, not its input: the simulation would be
#    self-referential and would prove nothing while looking right. So the script asks
#    `isEffectLoaded`, falls back to disabling the plugin (which KWin does honour, through
#    [Plugins] and /KWin reconfigure), and refuses to carry on if neither works.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID=macosglass2
SALIDA="${1:-/tmp}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
PLUGIN_TOCADO=0

efecto() { # efecto <Method>
    timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects."$1" "$ID" >/dev/null 2>&1
}

cargado() { # cargado -> "true" | "false" | ""
    timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$ID" 2>/dev/null \
        | tr -d '[:space:]'
}

# ONE parser, used by the test mode AND by the capture, so that a test of it is a test of the step
# that runs. An earlier version tested a parser while the capture used a different one, and the
# capture failed on every run while the test passed.
parse_geometria() { # parse_geometria "<x,y,w,h,bar>" -> "x y w h bar" or nothing
    local g="$1" x y w h bar
    x=$(printf '%s' "$g" | cut -d, -f1 | cut -d. -f1)
    y=$(printf '%s' "$g" | cut -d, -f2 | cut -d. -f1)
    w=$(printf '%s' "$g" | cut -d, -f3 | cut -d. -f1)
    h=$(printf '%s' "$g" | cut -d, -f4 | cut -d. -f1)
    bar=$(printf '%s' "$g" | cut -d, -f5 | cut -d. -f1)
    if [ -z "$x" ] || [ -z "$y" ] || [ -z "$w" ] || [ -z "$h" ] || [ -z "$bar" ] || [ "$bar" = "0" ]; then
        return 1
    fi
    printf '%s %s %s %s %s\n' "$x" "$y" "$w" "$h" "$bar"
}

if [ "${1:-}" = "--geometry" ]; then
    parse_geometria "${2:-}" || { echo "could not parse that geometry"; exit 2; }
    exit 0
fi

# The active window, right now, through KWin's own scripting -- not the journal, which is stale.
leer_geometria() {
    cat > /tmp/glass-geom.js <<'JS'
const wins = workspace.windowList ? workspace.windowList() : workspace.clientList();
let best = null;
for (const w of wins) { if (w.normalWindow && w.active) best = w; }
if (best) print(`G|${best.frameGeometry.x},${best.frameGeometry.y},${best.frameGeometry.width},${best.frameGeometry.height},${best.clientGeometry.y - best.frameGeometry.y}`);
JS
    timeout 20 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/glass-geom.js >/dev/null 2>&1
    timeout 10 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1
    sleep 1
    local g
    g=$(timeout 15 journalctl --user --since '15 sec ago' -o cat 2>/dev/null | grep '^G|' | grep -v systemd-run | tail -1 | cut -d'|' -f2)
    [ -n "$g" ] || return 1
    parse_geometria "$g"
}

descargar() { # leaves the effect unloaded, or reports failure
    efecto unloadEffect
    sleep 2
    if [ "$(cargado)" != "false" ]; then
        # The D-Bus unload was refused. KWin does honour [Plugins], through the one reconfigure
        # command that reaches its own effect list.
        kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" false
        timeout 20 qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1
        sleep 2
        PLUGIN_TOCADO=1
    fi
    [ "$(cargado)" = "false" ]
}

cargar() { # undoes descargar, both ways round
    if [ "$PLUGIN_TOCADO" = "1" ]; then
        kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" true
        timeout 20 qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1
        sleep 1
    fi
    efecto loadEffect
}

restaurar() {
    cargar
    echo
    echo "the effect is loaded again ($(cargado))."
}
trap restaurar EXIT INT TERM

echo "asking KWin for the active window's geometry..."
leidos=$(leer_geometria) || {
    echo "  KWin did not report it. Focus the window whose title bar you want and run this again."
    exit 1
}
set -- $leidos
X=$1; Y=$2; ANCHO=$3; ALTO=$4; bar=$5
echo "  -> x=$X y=$Y w=$ANCHO title bar=${bar}px"

echo
echo "1/3 unloading the effect, so the capture shows the THEME and not the glass..."
if ! descargar; then
    echo "  could not unload the effect, and nothing was captured on purpose:"
    echo "  a capture with the effect on is its OUTPUT, not its input."
    exit 1
fi
echo "  unloaded ($(cargado))."
if ! timeout 20 spectacle -b -n -o "$SALIDA/_par_titulo.png" >/dev/null 2>&1; then
    echo "  spectacle could not capture the screen"
    exit 1
fi

echo
echo "2/3 MOVE THE ACTIVE WINDOW AWAY from x=$X..$((X+ANCHO)), y=$Y..$((Y+ALTO))"
echo "    (any direction is fine, as long as that region shows the desktop)"
read -r -p "    then press Enter... " _

if ! timeout 20 spectacle -b -n -o "$SALIDA/_par_fondo.png" >/dev/null 2>&1; then
    echo "  spectacle could not capture the screen"
    exit 1
fi

echo
echo "3/3 cropping both to the same strip..."
python3 - "$SALIDA" "$X" "$Y" "$ANCHO" "$bar" <<'PYEOF'
import sys
from PIL import Image
salida, x, y, w, bar = sys.argv[1], *(int(v) for v in sys.argv[2:6])
recorte = (x, y, x + w, y + bar)          # the title strip only: that is the band
for origen, destino in (("_par_titulo.png", "titulo.png"), ("_par_fondo.png", "fondo.png")):
    im = Image.open(f"{salida}/{origen}").convert("RGB")
    im.crop(recorte).save(f"{salida}/{destino}")
    print(f"  {salida}/{destino}  {im.crop(recorte).size[0]}x{im.crop(recorte).size[1]}")
PYEOF

echo
echo "Now, with the effect loaded again:"
echo "  python3 $HERE/simulate.py --window $SALIDA/titulo.png --backdrop $SALIDA/fondo.png --out $SALIDA/banda.png"
