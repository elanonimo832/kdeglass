#!/usr/bin/env bash
# M1.3a live: does the title bar SHOW the background behind the window?
#
# Asks the user to move ONE window so its title bar sits over two different
# backgrounds, captures at each, and compares the bar's own colour. A translucent
# bar changes; an opaque one does not, however much it blurs its own content.
#
# No sudo. Reads the window geometry from KWin's scripting API.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/glass"; mkdir -p "$OUT"

# The window geometry, straight from KWin, so the band can be located exactly.
get_window() {
  cat > /tmp/glass-win.js <<'JS'
const wins = workspace.windowList ? workspace.windowList() : workspace.clientList();
let best = null;
for (const w of wins) {
    if (!w.normalWindow || !w.active) continue;
    best = w;
}
if (best) {
    print(`M|${best.frameGeometry.x},${best.frameGeometry.y},${best.frameGeometry.width},${best.clientGeometry.y - best.frameGeometry.y}`);
}
JS
  timeout 20 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/glass-win.js >/dev/null 2>&1
  timeout 10 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1
  sleep 1
  timeout 15 journalctl --user --since '6 sec ago' -o cat 2>/dev/null | grep '^M|' | grep -v systemd-run | tail -1 | cut -d'|' -f2
}

echo "=== M1.3a: does the bar show the background? ==="
echo
echo "  Move the window so its TITLE BAR sits over a DARK part of the screen,"
read -r -p "  then press Enter... " _
g=$(get_window)
[ -z "$g" ] && { echo "  ABORTED: could not read the window geometry."; exit 1; }
x=$(echo "$g" | cut -d, -f1 | cut -d. -f1)
y=$(echo "$g" | cut -d, -f2 | cut -d. -f1)
w=$(echo "$g" | cut -d, -f3 | cut -d. -f1)
bar=$(echo "$g" | cut -d, -f4 | cut -d. -f1)
echo "  window: x=$x y=$y w=$w bar=$bar"
spectacle -b -n -o "$OUT/over-dark.png" >/dev/null 2>&1 || true

echo
echo "  Now move it over a LIGHT part of the screen."
read -r -p "  then press Enter... " _
g2=$(get_window)
[ -n "$g2" ] && { x=$(echo "$g2" | cut -d, -f1 | cut -d. -f1); y=$(echo "$g2" | cut -d, -f2 | cut -d. -f1); }
spectacle -b -n -o "$OUT/over-light.png" >/dev/null 2>&1 || true

echo
python3 "$HERE/measure-glass.py" "$OUT/over-dark.png" "$OUT/over-light.png" "$x" "$y" "$w" "$bar"
