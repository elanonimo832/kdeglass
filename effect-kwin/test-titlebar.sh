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

echo "3. Reading the window geometry the effect reported..."
line=$(timeout 20 journalctl --user --since '60 sec ago' -o cat 2>/dev/null \
        | grep 'title bar band' | grep -v systemd-run | tail -1)
if [ -z "$line" ]; then
  echo "  ABORTED: the effect logged no 'title bar band' line."
  echo "  Either it did not paint, or this build is not the installed one."
  echo "  Install and restart the session first:  ./install.sh"
  exit 1
fi
echo "  $line"

# frame= KWin::RectF(X,Y WxH)   barHeight= N
frame=$(printf '%s' "$line" | sed -n 's/.*frame= *KWin::RectF(\([^)]*\)).*/\1/p')
bar=$(printf '%s' "$line" | sed -n 's/.*barHeight= *\([0-9.]*\).*/\1/p' | cut -d. -f1)
x=$(printf '%s' "$frame" | cut -d' ' -f1 | cut -d, -f1)
y=$(printf '%s' "$frame" | cut -d' ' -f1 | cut -d, -f2)
w=$(printf '%s' "$frame" | cut -d' ' -f2 | cut -dx -f1)
h=$(printf '%s' "$frame" | cut -d' ' -f2 | cut -dx -f2)

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
