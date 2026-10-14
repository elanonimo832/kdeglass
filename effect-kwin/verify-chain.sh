#!/usr/bin/env bash
# Checks the root cause of the black screen: MacosGlassEffect::paintWindow()
# MUST continue the KWin chain by calling effects->paintWindow().
#
# EffectsHandler::paintWindow() calls ONE single effect; the chain advances because
# Effect::paintWindow() (the base) re-enters effects->paintWindow(). If an
# effect overrides paintWindow() and does not call the base, the chain is cut,
# finalPaintWindow() is not run and NO window is drawn (black background).
#
# NOTE on the grep: `grep -c ... >/dev/null` is used and NOT `grep -q`. With -q, grep
# aborts as soon as it finds the match and closes the pipe; combined with `pipefail`
# that gave a NON-DETERMINISTIC result (sometimes it passed, sometimes not). With -c it reads
# the whole input and the result is stable. See INCIDENT.md.
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUENTE="$AQUI/src/glass.cpp"
SO="$AQUI/build/plugins/kwin/effects/macosglass2.so"
SISTEMA=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so

fallo=0

echo "=== 1. The source calls effects->paintWindow() ==="
if grep -cE 'effects->paintWindow\(' "$FUENTE" >/dev/null; then
  echo "  OK: $FUENTE contains the chain call"
else
  echo "  FAIL: paintWindow() does NOT continue the chain -> black screen"
  fallo=1
fi

echo
echo "=== 2. The compiled binary calls EffectsHandler::paintWindow ==="
if [ ! -f "$SO" ]; then
  echo "  (not compiled yet; run: cmake --build build)"
  fallo=1
elif objdump -d --demangle "$SO" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null; then
  echo "  OK: $(basename "$SO") calls the chain"
else
  echo "  FAIL: the compiled binary does NOT call the chain"
  fallo=1
fi

echo
echo "=== 3. The .so installed on the system ==="
if [ ! -f "$SISTEMA" ]; then
  echo "  (no .so installed in $SISTEMA)"
  echo "  Install it with:  ./install.sh"
elif objdump -d --demangle "$SISTEMA" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null; then
  echo "  OK: the installed .so is the FIXED one"
else
  echo "  WARN: the installed .so does NOT carry the chain. Do NOT activate it."
  echo "         Reinstall:  ./install.sh"
  fallo=1
fi

echo
if [ "$fallo" -eq 0 ]; then
  echo "CHAIN OK: the effect cannot leave the screen black for this reason."
else
  echo "CHAIN BROKEN: do NOT activate this effect until it is fixed."
fi
exit "$fallo"
