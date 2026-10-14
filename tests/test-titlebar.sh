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

EF="$PROY/effect-kwin"
FUENTE="$EF/src/glass.cpp"
CABECERA="$EF/src/glass.h"

echo "  -- the blur is confined to a band, not the whole window --"
# The shader must decide per-fragment. A shader that blurs everywhere is what
# produced the unreadable window.
# The v axis of the offscreen texture runs opposite to window coordinates, so the
# distance from the window's TOP is (1 - vTexCoord.y). Testing vTexCoord.y directly
# put the band at the BOTTOM of every window -- caught by the user's screenshot,
# not by any measurement, because the test only asked whether SOME band blurred.
afirmar_codigo "the shader measures distance from the TOP" "$FUENTE" '1\.0 - vTexCoord\.y'
negar "the un-flipped expression is gone" grep -q 'float yPixels = vTexCoord.y \* uTextureSize.y' "$FUENTE"
afirmar_codigo "it compares against the band height" "$FUENTE" 'yPixelsFromTop > uTitleBarHeight'
afirmar_codigo "outside the band the original texel is used" "$FUENTE" 'texture\(sampler, vTexCoord\)'

echo "  -- the band height comes from the decoration, not from a guess --"
# A hard-coded height would be wrong for every theme but ours. KWin knows it.
# Measured, not assumed: the distance from the top of the frame to the top of the
# client area. Works for any decoration theme; a constant would only suit ours.
afirmar_codigo "the title bar height is measured from the window" "$FUENTE" 'clientGeometry\(\)\.top\(\) - w->frameGeometry\(\)\.top\(\)'
afirmar_codigo "it is passed to the shader as a uniform" "$FUENTE" 'uTitleBarHeight'

echo "  -- the uniforms are set while the shader is bound --"
# The bug that made M1.2a a silent no-op: setUniform is glUniform1f and writes to
# whichever program is active. Without a bind, uRadius stayed 0, every tap sampled
# the same texel, and the output equalled the input.
afirmar_codigo "the shader is bound around the uniform writes" "$FUENTE" 'pushShader'
afirmar_codigo "and unbound afterwards" "$FUENTE" 'popShader'

echo "  -- the measurement tool checks a band, not the whole image --"
afirmar_existe "measure-titlebar.py exists" "$EF/measure-titlebar.py"
