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

# VERIFY THE OBJECT BEFORE MEASURING IT (methodology rule 4).
#
# KWin loaded the INSTALLED .so at login; this directory holds the build we just
# wrote. If they differ, every number below describes the PREVIOUS effect, and the
# honest thing is to refuse than to print a verdict nobody can act on. Not
# hypothetical: when this guard was written, the installed plugin was the
# pre-capture build, so a relogin without ./install.sh would have measured the old
# alpha path and the result would have been read as "the capture does not work".
INSTALADO=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so
CONSTRUIDO="$HERE/build/plugins/kwin/effects/macosglass2.so"
if [ -f "$CONSTRUIDO" ] && [ -f "$INSTALADO" ] && ! cmp -s "$CONSTRUIDO" "$INSTALADO"; then
  echo "  ABORTED: the INSTALLED effect is not the build in this directory."
  echo "           installed: $INSTALADO"
  echo "           built:     $CONSTRUIDO"
  echo "           Run ./install.sh, log OUT and back IN, then run this again."
  echo "           Measuring now would describe the previous behaviour."
  exit 1
fi

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
echo "  -- what the effect itself says about the capture --"
# The measurement below can only say GLASS or OPAQUE. Those are TWO different OPAQUEs
# and this tells them apart: if the capture never happened (the GL context refused the
# blit), the band fell back to the old alpha path and "OPAQUE" says nothing about
# whether capturing the desktop is the right mechanism. Reading this here rather than
# a second command later is the difference between one relogin and two.
diag=$(timeout 20 journalctl --user --since '10 min ago' -o cat 2>/dev/null | grep 'macos-glass' | grep -v systemd-run)
captura=$(printf '%s\n' "$diag" | grep 'capture:' | tail -1)
if [ -n "$captura" ]; then
  echo "  $captura"
else
  echo "  (no 'capture:' line yet: either the effect is not loaded, or it has not"
  echo "   painted 60 times -- move a window a little and run this again)"
fi
# Only REAL trouble. The healthy line is "capture: ok=N refused=0", so matching the
# bare word `refused` printed four alarming WARNINGs about a capture that was working
# perfectly -- the first version of this filter did exactly that, and a false alarm is
# worse than no alarm: it teaches the reader to ignore the word. A non-zero refusal is
# what matters.
printf '%s\n' "$diag" | grep -E 'refused= *[1-9]|cannot allocate|not valid|failed to load|blit was refused' | tail -3 | sed 's/^/  WARNING: /'
echo

python3 "$HERE/measure-glass.py" "$OUT/behind-dark.png" "$OUT/behind-light.png" "$x" "$y" "$w" "$bar"
rc=$?

# Make the two OPAQUEs distinguishable in the verdict itself, not just in the log.
# Here-string, not a pipe into grep -q: under `set -o pipefail` the early exit of
# grep -q can kill the producer with SIGPIPE and report failure on a match. The
# project's own scan caught exactly that shape in the first version of this block.
if [ "$rc" -ne 0 ] && grep -q 'refused=0' <<< "$captura"; then
  echo
  echo "  NOTE: the desktop WAS captured (refused=0), so this OPAQUE is a COMPOSITE"
  echo "  problem -- the capture reaches the shader and the shader is not showing it."
else
  if [ "$rc" -ne 0 ]; then
    echo
    echo "  NOTE: check the capture line above. If refused is climbing, there was no"
    echo "  capture at all and the band is the old alpha path."
  fi
fi
exit "$rc"
