# M1.2 -- diffusion. The effect must SOFTEN the window content, not just tint it.
#
# M1.1 proved we can put pixels on screen. That says nothing about diffusion:
# a flat patch is M1.1, and blurring is a different mechanism (a shader over the
# window's offscreen texture, via OffscreenEffect, the base class KWin provides
# for exactly this).
#
# The measurable definition of blur: LOCAL CONTRAST DROPS. A blur removes
# high-frequency detail, so the standard deviation of pixel values across a
# window falls, while the mean stays roughly the same (blur redistributes, it does
# not add or remove light). That is what measure-diffusion.py checks.

EF="$PROY/effect-kwin"
FUENTE="$EF/src/glass.cpp"
CABECERA="$EF/src/glass.h"

echo "  -- the effect is an OffscreenEffect (the class KWin provides for this) --"
# An ordinary Effect can only clear regions. Transforming a window's own texture
# needs OffscreenEffect: it redirects the window into an offscreen texture and
# lets the effect replace the drawing with a shader.
afirmar_codigo "the class derives from OffscreenEffect" "$CABECERA" 'class MacosGlassEffect[[:space:]]*:[[:space:]]*public[[:space:]]+OffscreenEffect'
afirmar_contiene "offscreeneffect.h is included" "$CABECERA" 'offscreeneffect[.]h'

echo "  -- windows are redirected and given a shader --"
afirmar_codigo "windows are redirected" "$FUENTE" 'redirect[(]'
afirmar_codigo "a shader is applied to the window" "$FUENTE" 'setShader[(]'
afirmar_codigo "the shader is built at load time" "$FUENTE" 'generateCustomShader|ShaderManager'

echo "  -- the shader actually blurs --"
# One texture fetch per pixel is a copy, not a blur. The kernel accumulates
# inside a loop over a 3x3 neighbourhood, so the source has exactly one
# `sum += texture(...)` line that runs nine times at runtime. Counting source
# lines is the right check here: unrolling it would be nine literal fetches.
afirmar_codigo "the kernel accumulates texture samples" "$FUENTE" 'sum [+]= texture[(]'
# ERE: '(' is literal and '\(' opens a group, so the parenthesis needs a class.
afirmar_codigo "the sampling runs over a neighbourhood" "$FUENTE" 'for [(]int x = -1; x <= 1' 
afirmar_codigo "the result is averaged" "$FUENTE" 'sum /' 
afirmar_codigo "the blur radius is a named constant" "$CABECERA" 'kBlur|kFrost|kRadius'

echo "  -- the paint chain is still continued --"
# The old failure mode: an effect that overrides drawWindow/paintWindow and does
# not continue the chain leaves the screen black.
#
# The effect no longer calls the chain ITSELF, and that is correct: it derives
# from OffscreenEffect, whose drawWindow() calls effects->drawWindow() when the
# window is not redirected and OffscreenData::paint() when it is. Both paths
# verified in KWin 6.7's src/effect/offscreeneffect.cpp.
#
# So the check is on the BASE CLASS, not on a call of ours. Asserting our own call
# was wrong -- an earlier version of this test did exactly that and reported
# "chain broken" for a correct effect.
afirmar_codigo "derives from OffscreenEffect (which continues the chain)" "$CABECERA" 'public[[:space:]]+OffscreenEffect'
# CHANGED IN M1.3a. This used to assert the opposite -- that the effect does NOT
# override drawWindow -- and it was right for M1.2, where the base class did the
# whole job and overriding it was the known cause of two black screens. M1.3a needs
# the override: the desktop has to be captured before the window is painted, and
# drawWindow is the only place with the render target.
#
# The ban was the wrong test, not the override. What protects the screen is the
# property, and that is checked where it can be SHOWN to fail: verify-chain.sh with
# defective sources (tests/test-effect.sh) and the line below.
afirmar_codigo "the effect overrides drawWindow to capture the desktop" "$FUENTE" 'void MacosGlassEffect::drawWindow'
afirmar_codigo "and that override continues the chain" "$FUENTE" 'OffscreenEffect::drawWindow[(]'

echo "  -- the measurement tool exists --"
afirmar_existe "measure-diffusion.py exists" "$EF/measure-diffusion.py"
