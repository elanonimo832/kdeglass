#!/usr/bin/env bash
# LIVE test of the ALREADY INSTALLED effect. Installs nothing (no sudo needed).
# Always unloads when it finishes (trap EXIT).
#
# ---------------------------------------------------------------------------
# SUPERSEDED, AND ITS VERDICT CANNOT BE TRUSTED. READ THIS BEFORE RUNNING IT.
#
# It looks for the flat 48x48 MARKER that M1.1 drew to prove pixels could reach
# the screen. M1.2 replaced that marker with the material band, so the thing this
# script measures no longer exists: "not drawn" from here today is NOT evidence
# that the effect fails, and it will say that about a working build.
#
# The live instruments for the material now are:
#     ./test-glass.sh      does the band take colour from behind it? (M1.3a)
#     ./test-titlebar.sh   is the band blurred while the content stays sharp? (M1.2b)
#
# What is still true: everything below about HOW to measure by difference, and why
# colour matching against a desktop cannot work. That reasoning is why the other two
# tools compare regions instead of matching colours.
# ---------------------------------------------------------------------------
#
# It measures by DIFFERENCE: a screenshot with the effect OFF and one with it ON.
# The marker is the only thing that changes between them.
#
# Why not by colour, which is what the first version did: KWin composites through
# its own colour pipeline, so the value written with glClearColor is NOT the value
# that reaches the screen. Measured: writing 0x00E5FF produced #215055 -- a
# different colour, much darker. An exact-colour check therefore reports "not
# drawn" for a marker that is plainly visible, and that is exactly how this was
# first misdiagnosed. Colour matching against a desktop is also hopeless in
# general: the wallpaper held 1388 pixels within tolerance of the first marker
# colour. The difference between two screenshots has neither problem.
#
# NOTE ON HOT LOADING: KWin invites an already-visible window to repaint only when
# something damages it. Loading an effect hot therefore does not reliably reach
# paintWindow for existing windows. The effect calls effects->addRepaintFull() on
# load to force it, but the RELIABLE path is a fresh session, where KWin loads the
# effect at startup. If this reports NOT drawn, log out and back in, then:
#     spectacle -b -n -o /tmp/on.png && python3 measure-marker.py /tmp/off.png /tmp/on.png
set -uo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
ID=macosglass2
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/variants"; mkdir -p "$OUT"
PATCH=$((48 * 48))

unload() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$ID" >/dev/null 2>&1; }
trap 'unload' EXIT INT TERM

SISTEMA=/usr/lib/qt6/plugins/kwin/effects/plugins/$ID.so
if [ ! -f "$SISTEMA" ]; then
  echo "ABORTED: $SISTEMA does not exist. Install it first:  ./install.sh"
  exit 1
fi

echo "Effect: $ID (already installed). Nothing is installed by this script."

# The control MUST be captured with the effect actually OFF. The first version of
# this script did not force that, so the control already contained the marker and
# both numbers were meaningless.
echo "1. Effect OFF, capturing the control..."
unload; sleep 4
spectacle -b -n -o "$OUT/installed-control.png" >/dev/null 2>&1 || true

echo "2. Loading $ID ..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$ID" >/dev/null 2>&1
sleep 6
spectacle -b -n -o "$OUT/installed-loaded.png" >/dev/null 2>&1 || true

echo "3. Unloading..."
unload; sleep 3
spectacle -b -n -o "$OUT/installed-after-unload.png" >/dev/null 2>&1 || true

echo
python3 "$HERE/measure-marker.py" "$OUT/installed-control.png" "$OUT/installed-loaded.png" "$PATCH"
rc=$?

# Same check with the after-unload capture: if the marker is really the effect
# drawing, removing the effect must remove it.
echo
python3 "$HERE/measure-marker.py" "$OUT/installed-after-unload.png" "$OUT/installed-loaded.png" "$PATCH" \
  | sed 's/^/  (control = after-unload) /'
exit $rc
