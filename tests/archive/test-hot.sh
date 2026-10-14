#!/usr/bin/env bash
# HOT test of the M1.1 patch, WITHOUT logging out.
#
# Why this can work: KWin repaints a window when something DAMAGES it -- moving
# it, resizing it, changing focus. Loading an effect does NOT damage anything, so
# a plain loadEffect leaves existing windows unpainted and paintWindow is never
# called for them. Loading alone is therefore not enough, which is what the
# earlier hot attempts got wrong.
#
# This script loads the effect and then DAMAGES windows on purpose, so
# paintWindow is reached. No sudo, no logout.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
ID=macosglass2
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/hot"; mkdir -p "$OUT"

unload() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$ID" >/dev/null 2>&1; }
trap 'unload' EXIT INT TERM

echo "=== HOT test of the M1.1 patch (no logout) ==="

echo "1. Effect OFF; capturing the control..."
unload; sleep 3
spectacle -b -n -o "$OUT/hot-control.png" >/dev/null 2>&1 || true

echo "2. Loading $ID ..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$ID" >/dev/null 2>&1
sleep 2
printf '   isEffectLoaded: %s\n' "$(timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded $ID 2>&1)"

echo
echo "3. NOW DAMAGE THE WINDOWS. For the next 25 seconds:"
echo "      - click a window's title bar and DRAG it around"
echo "      - resize a window"
echo "      - switch focus between two windows"
echo "   Keep moving something the whole time."
echo
for i in $(seq 25 -1 1); do printf '\r   %2d s ... ' "$i"; sleep 1; done
printf '\r                      \n'

spectacle -b -n -o "$OUT/hot-loaded.png" >/dev/null 2>&1 || true

echo "4. Unloading; capturing after-unload..."
unload; sleep 3
spectacle -b -n -o "$OUT/hot-after.png" >/dev/null 2>&1 || true

echo
echo "5. How many times did paintWindow run?"
n=$(timeout 20 journalctl --user --since '60 sec ago' -o cat 2>/dev/null | grep -c 'CALIB')
echo "   CALIB lines in the journal: $n"
if [ "$n" -gt 0 ]; then
  timeout 20 journalctl --user --since '60 sec ago' -o cat 2>/dev/null \
    | grep 'CALIB' | grep -v systemd-run | tail -3 | sed 's/^/   /'
fi

echo
echo "=== RESULT ==="
# CAVEAT: the difference measurement is spoiled if you MOVE windows, because the
# windows themselves change. In the first hot run, dragging produced 2,764,537
# changed pixels against 2304 for one patch, and the verdict was meaningless.
# For a trustworthy number, damage a window WITHOUT moving it: click its title
# bar, resize by a pixel, or switch focus between two windows.
python3 "$HERE/measure-marker.py" "$OUT/hot-control.png" "$OUT/hot-loaded.png" "$((48*48))"
