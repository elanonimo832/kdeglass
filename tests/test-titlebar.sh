# M1.2b -- the material applies to the TITLE BAR ONLY.
#
# Full-window diffusion was verified working and is unusable: it blurs the content
# you are reading. macOS never does that. Its material covers the window CHROME
# (title bar, toolbars, sidebars) and the content stays sharp.
#
# Option A, chosen deliberately: only the title bar. It is the one surface KWin
# tells an effect about explicitly -- frameGeometry() plus the decoration's title
# bar height. Sidebars and toolbars would have to be guessed, and guessing geometry
# is what cost four session restarts in M1.1.

EF="$PROJECT/effect-kwin"
SOURCE="$EF/src/glass.cpp"
HEADER="$EF/src/glass.h"

echo "  -- the blur is confined to a band, not the whole window --"
# The shader must decide per-fragment. A shader that blurs everywhere is what
# produced the unreadable window.
# The v axis of the offscreen texture runs opposite to window coordinates, so the
# distance from the window's TOP is (1 - vTexCoord.y). Testing vTexCoord.y directly
# put the band at the BOTTOM of every window -- caught by the user's screenshot,
# not by any measurement, because the test only asked whether SOME band blurred.
afirmar_codigo "the shader measures distance from the TOP" "$SOURCE" '1\.0 - vTexCoord\.y'
negar "the un-flipped expression is gone" grep -q 'float yPixels = vTexCoord.y \* uTextureSize.y' "$SOURCE"
afirmar_codigo "it compares against the band height" "$SOURCE" 'yPixelsFromTop > uTitleBarHeight'
afirmar_codigo "outside the band the original texel is used" "$SOURCE" 'texture[(]sampler, vTexCoord[)]'

echo "  -- the band height comes from the decoration, not from a guess --"
# A hard-coded height would be wrong for every theme but ours. KWin knows it.
# Measured, not assumed: the distance from the top of the frame to the top of the
# client area. Works for any decoration theme; a constant would only suit ours.
afirmar_codigo "the title bar height is measured from the window" "$SOURCE" 'clientGeometry[(][)]\.top[(][)] - w->frameGeometry[(][)]\.top[(][)]'
afirmar_codigo "it is passed to the shader as a uniform" "$SOURCE" 'uTitleBarHeight'

echo "  -- the uniforms are set while the shader is bound --"
# The bug that made M1.2a a silent no-op: setUniform is glUniform1f and writes to
# whichever program is active. Without a bind, uRadius stayed 0, every tap sampled
# the same texel, and the output equalled the input.
afirmar_codigo "the shader is bound around the uniform writes" "$SOURCE" 'pushShader'
afirmar_codigo "and unbound afterwards" "$SOURCE" 'popShader'

echo "  -- the measurement tool checks a band, not the whole image --"
afirmar_existe "measure-titlebar.py exists" "$EF/measure-titlebar.py"

echo "  -- the shader is re-asserted on every paint --"
# setShader() once, at window-add time, was not enough: the band vanished as soon
# as the window was moved or focus changed, because KWin repaints on those events
# and the paint path does not keep the shader registered at add time. apply() runs
# on EVERY paint, so that is where it has to be re-asserted.
# Checked across lines with awk: the assertion is about what the apply() BODY
# contains, and grep works line by line, so it cannot see that.
# awk is captured first instead of piped into `grep -q`: under `set -o pipefail`
# the early exit of grep -q kills awk with SIGPIPE and the pipeline fails on a
# match, at random. See tests/test-harness.sh.
if grep -q -- 'setShader(' <<< "$(awk '/void MacosGlassEffect::apply/,/^}/' "$SOURCE")"; then
  ok "apply() re-asserts the shader on every paint"
else
  fallo "apply() does not re-assert the shader (the band will vanish on repaint)"
fi

echo "  -- the uniforms are set per paint, not once per window --"
# The shader is ONE object shared by every window. Setting its uniforms in
# slotWindowAdded meant the last window added won: uTitleBarHeight held another
# window's bar height, and every focus change overwrote it. That is why the
# material flickered away and came back when switching windows.
if grep -q 'uTitleBarHeight' <<< "$(awk '/void MacosGlassEffect::apply/,/^}/' "$SOURCE")"; then
  ok "apply() sets the band height per window"
else
  fallo "the band height is not set per paint (shared-shader bug is back)"
fi
# Comments excluded: the comment EXPLAINS why the shared shader must not be
# written here, and matching that explanation made this assertion fail on correct
# code. Same trap as several earlier tests in this project.
if grep -q 'setUniform' <<< "$(awk '/void MacosGlassEffect::slotWindowAdded/,/^}/' "$SOURCE" | grep -vE '^[[:space:]]*//')"; then
  fallo "slotWindowAdded still sets uniforms on the shared shader"
else
  ok "slotWindowAdded no longer writes to the shared shader"
fi

echo "  -- the measurement separates 'not applied' from 'applied but not blurred' --"
# M1.3a step 2 puts the SHARP captured desktop in the band, so the M1.2b criterion
# ("the band loses edge energy") is legitimately not met while the effect works.
# The tool used to call that "NOT APPLIED": a false alarm aimed straight at the next
# relogin, and this project has already paid for an instrument that answered the
# wrong question. Synthetic images, so the instrument is checked without a screen.
if ! python3 -c 'import PIL, numpy' >/dev/null 2>&1; then
  ok "(SKIPPED: Pillow/numpy are not installed; measure-titlebar.py was NOT exercised)"
else
  BOX="$(mktemp -d)"
  python3 - "$BOX" <<'PYEOF'
import pathlib, sys
import numpy as np
from PIL import Image

d = pathlib.Path(sys.argv[1])
X, Y, W, H, BAR = 20, 20, 160, 120, 30
FILA, COL = slice(Y + 3, Y + BAR - 3), slice(X + 3, X + W - 3)


def con_banda(banda):
    img = np.full((240, 240, 3), 30, dtype=np.uint8)
    # the content: a checkerboard that must stay sharp in all three cases
    idx = np.indices((H - BAR - 6, W - 6)).sum(axis=0)
    img[Y + BAR + 3:Y + H - 3, X + 3:X + W - 3] = np.where(((idx // 4) % 2)[..., None] == 0, 200, 40)
    img[FILA, COL] = banda[..., None]
    return img


rayas_v = np.where(((np.indices((BAR - 6, W - 6))[1] // 3) % 2) == 0, 240, 20)
rayas_h = np.where(((np.indices((BAR - 6, W - 6))[0] // 3) % 2) == 0, 240, 20)
uniforme = np.full((BAR - 6, W - 6), 130)

Image.fromarray(con_banda(rayas_v)).save(d / "off.png")
Image.fromarray(con_banda(uniforme)).save(d / "blurred.png")   # a real blur
Image.fromarray(con_banda(rayas_h)).save(d / "changed.png")    # step 2: sharp, different
Image.fromarray(con_banda(rayas_v)).save(d / "same.png")       # nothing happened
PYEOF
  ver() { python3 "$EF/measure-titlebar.py" "$BOX/off.png" "$BOX/$1" 20 20 160 120 30; }
  salida_bien="$(ver blurred.png)"; rc_bien=$?
  salida_cambio="$(ver changed.png)"; rc_cambio=$?
  salida_igual="$(ver same.png)"; rc_igual=$?

  afirmar_igual "a blurred band is still CORRECT (0)" "0" "$rc_bien"
  afirmar_igual "a band that changed but kept its detail is 3, not 1" "3" "$rc_cambio"
  afirmar_igual "an untouched band is still NOT APPLIED (1)" "1" "$rc_igual"
  # The verdict must say WHY keeping the detail is fine now, or the next reader will
  # read code 3 as "the blur is missing" -- which is exactly how the previous wording
  # went stale when the chrome started being drawn crisp on purpose.
  if grep -q 'crisp over the glass' <<< "$salida_cambio"; then
    ok "the kept-detail verdict explains that it is the design, not a failure"
  else
    fallo "the 'changed but not blurred' verdict does not explain itself"
  fi
  rm -rf "${BOX:?}"
fi
