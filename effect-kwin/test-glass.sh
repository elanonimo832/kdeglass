#!/usr/bin/env bash
# M1.3a live: does the title bar SHOW what is behind the window?
#
# THE EXPERIMENT MUST CHANGE ONE THING.
#
# The first version asked the user to move the window over a dark area and then a
# light one. That changes TWO things: the region being measured and the background
# behind it. It reported a difference of 189.5 and called it glass -- but it had
# simply compared two different parts of the screen. A false positive, and the user
# caught it by looking: "no veo efecto".
#
# This version keeps the WINDOW STILL and changes only what is BEHIND it.
# The bar rectangle is read once, so both captures compare the same pixels.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/glass"; mkdir -p "$OUT"

get_window() {
  cat > /tmp/glass-win.js <<'JS'
const wins = workspace.windowList ? workspace.windowList() : workspace.clientList();
let best = null;
for (const w of wins) { if (w.normalWindow && w.active) best = w; }
if (best) print(`M|${best.frameGeometry.x},${best.frameGeometry.y},${best.frameGeometry.width},${best.clientGeometry.y - best.frameGeometry.y}`);
JS
  timeout 20 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/glass-win.js >/dev/null 2>&1
  timeout 10 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1
  sleep 1
  timeout 15 journalctl --user --since '6 sec ago' -o cat 2>/dev/null | grep '^M|' | grep -v systemd-run | tail -1 | cut -d'|' -f2
}

echo "=== M1.3a: does the bar show the background? ==="
echo
echo "  DO NOT MOVE THE WINDOW during this test."
read -r -p "  Position it once, then press Enter... " _
g=$(get_window)
[ -z "$g" ] && { echo "  ABORTED: could not read the window geometry."; exit 1; }
x=$(echo "$g" | cut -d, -f1 | cut -d. -f1)
y=$(echo "$g" | cut -d, -f2 | cut -d. -f1)
w=$(echo "$g" | cut -d, -f3 | cut -d. -f1)
bar=$(echo "$g" | cut -d, -f4 | cut -d. -f1)
echo "  bar rectangle fixed at: x=$x y=$y w=$w bar=$bar"
echo "  It will NOT change. Only what is behind the window changes."
echo
read -r -p "  1. Make the area BEHIND the window DARK (switch to a dark desktop, or
     put a dark window behind it), then press Enter... " _
spectacle -b -n -o "$OUT/behind-dark.png" >/dev/null 2>&1 || true

read -r -p "  2. WITHOUT MOVING THIS WINDOW, make the area behind it LIGHT,
     then press Enter... " _
spectacle -b -n -o "$OUT/behind-light.png" >/dev/null 2>&1 || true

echo
python3 "$HERE/measure-glass.py" "$OUT/behind-dark.png" "$OUT/behind-light.png" "$x" "$y" "$w" "$bar"
