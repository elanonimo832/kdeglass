#!/usr/bin/env bash
# M1.2b live check: the material covers the title bar and leaves the content sharp.
#
# It captures with the effect OFF and ON, reads the window geometry and the title
# bar height from the effect's own log, and measures the two regions separately.
#
# No sudo. Always unloads at the end (trap EXIT).
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
ID=macosglass2
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/titlebar"; mkdir -p "$OUT"

unload() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$ID" >/dev/null 2>&1; }
trap 'unload' EXIT INT TERM

echo "=== M1.2b: title bar only ==="

# The same freshness guard as test-glass.sh: KWin loaded the INSTALLED .so at login,
# and a verdict about a build that is not installed describes the previous effect.
INSTALADO=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so
CONSTRUIDO="$HERE/build/plugins/kwin/effects/macosglass2.so"
if [ -f "$CONSTRUIDO" ] && [ -f "$INSTALADO" ] && ! cmp -s "$CONSTRUIDO" "$INSTALADO"; then
  echo "  ABORTED: the INSTALLED effect is not the build in this directory."
  echo "           Run ./install.sh, log OUT and back IN, then run this again."
  exit 1
fi

echo "1. Effect OFF; capturing..."
unload; sleep 4
spectacle -b -n -o "$OUT/off.png" >/dev/null 2>&1 || true

echo "2. Loading $ID ..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$ID" >/dev/null 2>&1
sleep 3
# damage a window without moving it, so the repaint reaches the effect
echo "   (clicking a title bar would help; waiting 6 s)"
sleep 6
spectacle -b -n -o "$OUT/on.png" >/dev/null 2>&1 || true

echo "3. Reading the geometry of the ACTIVE window..."
# The first version read the effect's own "title bar band:" line from the journal,
# and that line is emitted for the first six windows of the PROCESS (a counter in
# slotWindowAdded). After a hot reload the library stays mapped, the counter is
# already spent, no new line appears -- and the script aborted saying "either it did
# not paint, or this build is not the installed one", which was wrong and alarming:
# the effect was painting fine. Asking KWin for the geometry cannot go stale.
cat > /tmp/titlebar-win.js <<'JS'
const wins = workspace.windowList ? workspace.windowList() : workspace.clientList();
let best = null;
for (const w of wins) { if (w.normalWindow && w.active) best = w; }
if (best) print(`G|${best.frameGeometry.x},${best.frameGeometry.y},${best.frameGeometry.width},${best.frameGeometry.height},${best.clientGeometry.y - best.frameGeometry.y}`);
JS
timeout 20 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/titlebar-win.js >/dev/null 2>&1
timeout 10 qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1
sleep 1
g=$(timeout 15 journalctl --user --since '15 sec ago' -o cat 2>/dev/null | grep '^G|' | grep -v systemd-run | tail -1 | cut -d'|' -f2)
if [ -z "$g" ]; then
  echo "  ABORTED: KWin did not report the active window's geometry."
  echo "  Focus the window you want to measure and run this again."
  exit 1
fi
x=$(printf '%s' "$g" | cut -d, -f1 | cut -d. -f1)
y=$(printf '%s' "$g" | cut -d, -f2 | cut -d. -f1)
w=$(printf '%s' "$g" | cut -d, -f3 | cut -d. -f1)
h=$(printf '%s' "$g" | cut -d, -f4 | cut -d. -f1)
bar=$(printf '%s' "$g" | cut -d, -f5 | cut -d. -f1)

echo "  parsed: x=$x y=$y w=$w h=$h bar=$bar"
if [ -z "$x" ] || [ -z "$bar" ] || [ "$bar" = "0" ]; then
  echo "  ABORTED: could not parse the geometry, or the window has no title bar."
  exit 1
fi

echo
python3 "$HERE/measure-titlebar.py" "$OUT/off.png" "$OUT/on.png" "$x" "$y" "$w" "$h" "$bar"
rc=$?

echo
echo "Unloading..."
unload
exit $rc
