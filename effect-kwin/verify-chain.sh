#!/usr/bin/env bash
# THE CHECK THAT PREVENTS THE BLACK SCREEN.
#
# The incident: EffectsHandler::drawWindow() calls ONE effect at a time and the
# chain advances because the BASE implementation re-enters it. An effect that
# overrides drawWindow()/paintWindow() and does NOT continue the chain cuts it
# there: finalPaintWindow() never runs, no window is painted, and the screen goes
# black -- while KWin and plasmashell stay alive and answer on D-Bus.
#
# WHAT CHANGED IN M1.2, AND WHY THE OLD CHECK WAS WRONG
#   M1.1 overrode paintWindow() and had to call effects->paintWindow() itself, so
#   this script looked for that call in our source and in our binary.
#
#   M1.2 derives from OffscreenEffect, which continues the chain for us: its
#   drawWindow() calls effects->drawWindow() when the window is not redirected and
#   OffscreenData::paint() when it is. Both paths verified in KWin 6.7's
#   src/effect/offscreeneffect.cpp.
#
#   Looking for our own call therefore reports "chain broken" for a correct
#   effect. This script printed exactly that false alarm and blocked the install.
#   The dangerous thing to look for is not a MISSING call -- it is an OVERRIDE
#   that forgets one. So that is what is checked.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$HERE/src/glass.cpp"
HEADER="$HERE/src/glass.h"
SO="$HERE/build/plugins/kwin/effects/macosglass2.so"
SYSTEM_SO=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so

fallo=0

echo "=== 1. The effect must not override the chain entry points ==="
# Overriding either of these means the effect took responsibility for continuing
# the chain, and must then prove it does. Not overriding is the safe state: the
# base class handles it.
for fn in drawWindow paintWindow; do
  if grep -qE "void MacosGlassEffect::$fn" "$SOURCE" 2>/dev/null; then
    if grep -qE 'effects->(drawWindow|paintWindow)\(' "$SOURCE" 2>/dev/null; then
      echo "  OK: overrides $fn and calls the chain"
    else
      echo "  FAIL: overrides $fn and does NOT call the chain -> black screen"
      fallo=1
    fi
  else
    echo "  OK: does not override $fn (the base class continues the chain)"
  fi
done

echo
echo "=== 2. The base class must be one that continues the chain ==="
# Effect::drawWindow and Effect::paintWindow re-enter the chain. OffscreenEffect
# overrides drawWindow but calls effects->drawWindow() on every path.
if grep -qE 'public[[:space:]]+OffscreenEffect' "$HEADER" 2>/dev/null; then
  echo "  OK: derives from OffscreenEffect (continues the chain in both paths)"
elif grep -qE 'public[[:space:]]+Effect' "$HEADER" 2>/dev/null; then
  echo "  OK: derives from Effect (its drawWindow re-enters the chain)"
else
  echo "  FAIL: unknown base class -- cannot confirm the chain is continued"
  fallo=1
fi

echo
echo "=== 3. The base class must actually be linked into the plugin ==="
# A derived class that links nothing of its base cannot have picked up its
# behaviour. This is the check that replaces the old "our binary calls the chain".
if [ ! -f "$SO" ]; then
  echo "  (not compiled yet; run: ./build.sh)"
  fallo=1
elif nm -D --undefined-only "$SO" 2>/dev/null | grep -q 'OffscreenEffect'; then
  echo "  OK: $(basename "$SO") links OffscreenEffect"
else
  echo "  FAIL: the plugin does not link OffscreenEffect"
  fallo=1
fi

echo
echo "=== 4. The installed plugin ==="
if [ ! -f "$SYSTEM_SO" ]; then
  echo "  (no plugin installed in $SYSTEM_SO)"
  echo "  Install it with:  ./install.sh"
elif nm -D --undefined-only "$SYSTEM_SO" 2>/dev/null | grep -q 'OffscreenEffect'; then
  echo "  OK: the installed plugin links OffscreenEffect"
else
  echo "  WARN: the installed plugin is an older build. Do not activate it."
  fallo=1
fi

echo
if [ "$fallo" -eq 0 ]; then
  echo "CHAIN OK: nothing overrides the chain without continuing it."
else
  echo "CHAIN AT RISK: do NOT activate this effect."
fi
exit "$fallo"
