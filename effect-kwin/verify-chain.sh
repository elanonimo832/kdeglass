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
#
# USAGE
#   ./verify-chain.sh            full check, includes the INSTALLED plugin
#   ./verify-chain.sh --source   skip the installed plugin (what install.sh needs)
#
# WHY --source EXISTS. install.sh runs this BEFORE copying the new build into
# place. Checking the installed plugin there is circular: an older installed build
# fails the check, and that failure blocks the very install that would replace it.
# The install was blocked exactly that way. So install.sh checks the SOURCE and
# the BUILD it is about to install; the installed copy is replaced immediately
# afterwards anyway.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ONLY=no
[ "${1:-}" = "--source" ] && SOURCE_ONLY=yes
SOURCE="$HERE/src/glass.cpp"
HEADER="$HERE/src/glass.h"
SO="$HERE/build/plugins/kwin/effects/macosglass2.so"
SYSTEM_SO=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so

# --diagnose: prints what each check actually sees. Added after this script
# reported "does not link OffscreenEffect" on a binary where the same nm command
# printed 11 matching symbols. The failure could not be reproduced elsewhere, so
# rather than guess again, the script now shows its own inputs.
if [ "${1:-}" = "--diagnose" ] || [ "${2:-}" = "--diagnose" ]; then
  echo "=== DIAGNOSE ==="
  echo "  pwd            : $(pwd)"
  echo "  BASH_SOURCE    : ${BASH_SOURCE[0]}"
  echo "  HERE           : $HERE"
  echo "  SO             : $SO"
  echo "  exists         : $([ -f "$SO" ] && echo yes || echo NO)"
  echo "  readable       : $([ -r "$SO" ] && echo yes || echo NO)"
  echo "  size           : $([ -f "$SO" ] && stat -c%s "$SO" || echo -)"
  echo "  bash version   : $BASH_VERSION"
  echo "  shell options  : $-"
  echo "  command -v nm  : $(command -v nm || echo 'NOT FOUND')"
  echo "  command -v grep: $(command -v grep || echo 'NOT FOUND')"
  echo
  echo "  nm exit code   :"
  nm -D --undefined-only "$SO" > /tmp/vc-nm.txt 2>/tmp/vc-nm.err
  echo "    nm exit=$?"
  echo "    nm stdout lines=$(wc -l < /tmp/vc-nm.txt)"
  echo "    nm stderr: $(head -2 /tmp/vc-nm.err)"
  echo "    OffscreenEffect matches=$(grep -c OffscreenEffect /tmp/vc-nm.txt)"
  echo
  echo "  pipeline result (the exact expression used at line 82):"
  if nm -D --undefined-only "$SO" 2>/dev/null | grep -q 'OffscreenEffect'; then
    echo "    -> PASA"
  else
    echo "    -> FALLA"
  fi
  echo
  echo "  same pipeline WITHOUT pipefail:"
  set +o pipefail
  if nm -D --undefined-only "$SO" 2>/dev/null | grep -q 'OffscreenEffect'; then
    echo "    -> PASA"
  else
    echo "    -> FALLA"
  fi
  set -o pipefail
  echo
  echo "  grep -c version (deterministic):"
  if nm -D --undefined-only "$SO" 2>/dev/null | grep -c 'OffscreenEffect' >/dev/null; then
    echo "    -> PASA"
  else
    echo "    -> FALLA"
  fi
  rm -f /tmp/vc-nm.txt /tmp/vc-nm.err
  exit 0
fi

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

if [ "$SOURCE_ONLY" = yes ]; then
  echo
  echo "=== 4. The installed plugin: SKIPPED (--source) ==="
  echo "  install.sh checks the source and the build it is about to install."
else
  echo
  echo "=== 4. The installed plugin ==="
  # This is reported but does NOT set the failure flag: a stale installed plugin is
  # not a broken chain, it is a plugin that needs replacing. Conflating the two is
  # what made this script block the install.
  if [ ! -f "$SYSTEM_SO" ]; then
    echo "  (none installed in $SYSTEM_SO)"
  elif nm -D --undefined-only "$SYSTEM_SO" 2>/dev/null | grep -q 'OffscreenEffect'; then
    echo "  OK: the installed plugin links OffscreenEffect"
  else
    echo "  NOTE: the installed plugin is an older build (does not link"
    echo "        OffscreenEffect). Install the current one:  ./install.sh"
  fi
fi

echo
if [ "$fallo" -eq 0 ]; then
  echo "CHAIN OK: nothing overrides the chain without continuing it."
else
  echo "CHAIN AT RISK: an override does not continue the chain. Do NOT activate."
fi
exit "$fallo"
