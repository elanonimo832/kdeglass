#!/usr/bin/env bash
# LIVE test of the ALREADY INSTALLED effect. Installs nothing (no sudo needed).
# Loads, measures and ALWAYS unloads (trap EXIT).
#
# It measures TWO things:
#   black  -- did the effect break rendering? (the incident's failure mode)
#   marker -- did it actually DRAW? (M1.1: a flat magenta patch)
#
# Before M1.1 the only assertion possible was black=0%, which proves the effect
# does not BREAK rendering but says nothing about whether it draws. The marker
# count is what makes "it draws" testable.
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
ID=macosglass2
OUT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build/variants"; mkdir -p "$OUT"

unload() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$ID" >/dev/null 2>&1; }
trap 'unload' EXIT INT TERM

measure() { # measure <label>
  local f="$OUT/installed-$1.png"; rm -f "$f"
  timeout 25 spectacle -b -n -o "$f" >/dev/null 2>&1 || true
  python3 - "$f" "$1" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.getdata()); n = len(px)
    black = sum(1 for r, g, b in px if r < 8 and g < 8 and b < 8)
    # M1.1 marker colour: 0xB3 / 0x3A / 0x5B. The tolerance absorbs compositing
    # and PNG round-tripping; nothing else in output/ is near this colour.
    mr, mg, mb = 0xB3, 0x3A, 0x5B
    marker = sum(1 for r, g, b in px if abs(r-mr) < 24 and abs(g-mg) < 24 and abs(b-mb) < 24)
    print(f"    {sys.argv[2]:14s} black={100*black/n:5.1f}%  marker={marker} px")
except Exception as e:
    print(f"    {sys.argv[2]}: could not measure ({e})")
PY
}

# Safety: refuse to run if the installed .so is not the one with M1.1. Loading an
# old build would measure nothing and, worse, would look like a result.
SISTEMA=/usr/lib/qt6/plugins/kwin/effects/plugins/$ID.so
if [ ! -f "$SISTEMA" ]; then
  echo "ABORTED: $SISTEMA does not exist. Install it first:  ./install.sh"
  exit 1
fi
if ! objdump -d "$SISTEMA" 2>/dev/null | grep -c glScissor >/dev/null; then
  echo "ABORTED: the installed .so has no M1.1 marker (no glScissor call)."
  echo "  installed: $SISTEMA  ($(stat -c%y "$SISTEMA" | cut -c1-19))"
  echo "  built    : build/plugins/kwin/effects/$ID.so  ($(stat -c%y "build/plugins/kwin/effects/$ID.so" | cut -c1-19))"
  echo "Install the new one first:  sudo install -Dm755 build/plugins/kwin/effects/$ID.so $SISTEMA"
  exit 1
fi
echo "Effect: $ID (already installed). Nothing is installed by this script."
measure control
echo "Loading $ID ..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$ID" >/dev/null 2>&1
sleep 5; measure loaded
echo "Unloading..."; unload; sleep 3; measure after-unload

python3 - "$OUT/installed-control.png" "$OUT/installed-loaded.png" <<'PY'
import sys
from PIL import Image
def stats(path):
    im = Image.open(path).convert("RGB"); px = list(im.getdata()); n = len(px)
    black = 100 * sum(1 for r, g, b in px if r < 8 and g < 8 and b < 8) / n
    mr, mg, mb = 0xB3, 0x3A, 0x5B
    marker = sum(1 for r, g, b in px if abs(r-mr) < 24 and abs(g-mg) < 24 and abs(b-mb) < 24)
    return black, marker
try:
    cb, cm = stats(sys.argv[1])
    lb, lm = stats(sys.argv[2])
    print()
    print(f"  control : black={cb:5.1f}%  marker={cm:7d} px")
    print(f"  loaded  : black={lb:5.1f}%  marker={lm:7d} px")
    delta = lm - cm
    print()
    if lb > 90:
        print("VERDICT: BREAKS rendering (black screen)")
    elif delta <= 0:
        print(f"VERDICT: does NOT draw -- marker pixels did not rise ({delta:+d})")
    else:
        print(f"VERDICT: DRAWS. black={lb:.1f}%, marker pixels {delta:+d} (M1.1 works)")
except Exception as e:
    print("could not measure:", e)
PY
