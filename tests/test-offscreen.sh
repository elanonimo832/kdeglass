# The MECHANISM test: the effect must derive from OffscreenEffect, redirect windows and
# hand them a shader, and it must continue KWin's paint chain on every path.
#
# This file was called test-diffusion.sh and opened with "M1.2 -- diffusion. The effect must
# SOFTEN the window content, not just tint it." That is no longer what it asserts or what
# the design claims: since M1.3a the frost lives on the CAPTURED BACKDROP, and the kernel
# over the window's own texture is what produces the band's tone and the chrome's baseline.
# A file whose name and opening paragraph describe a superseded mechanism is the same defect
# as a comment that lies, so the name and the header follow the assertions now.
#
# The blur claim itself is still measured -- by measure-titlebar.py (the title bar loses
# local contrast while the client area keeps it) and by test-glass.sh (the band shows the
# desktop behind it). What is left here is the machinery that makes both possible.

EF="$PROJECT/effect-kwin"
SOURCE="$EF/src/glass.cpp"
HEADER="$EF/src/glass.h"

echo "  -- the effect is an OffscreenEffect (the class KWin provides for this) --"
# An ordinary Effect can only clear regions. Transforming a window's own texture
# needs OffscreenEffect: it redirects the window into an offscreen texture and
# lets the effect replace the drawing with a shader.
afirmar_codigo "the class derives from OffscreenEffect" "$HEADER" 'class MacosGlassEffect[[:space:]]*:[[:space:]]*public[[:space:]]+OffscreenEffect'
afirmar_contiene "offscreeneffect.h is included" "$HEADER" 'offscreeneffect[.]h'

echo "  -- windows are redirected and given a shader --"
afirmar_codigo "windows are redirected" "$SOURCE" 'redirect[(]'
afirmar_codigo "a shader is applied to the window" "$SOURCE" 'setShader[(]'
afirmar_codigo "the shader is built at load time" "$SOURCE" 'generateCustomShader|ShaderManager'

echo "  -- the shader actually blurs --"
# One texture fetch per pixel is a copy, not a blur. The kernel accumulates
# inside a loop over a 3x3 neighbourhood, so the source has exactly one
# `sum += texture(...)` line that runs nine times at runtime. Counting source
# lines is the right check here: unrolling it would be nine literal fetches.
afirmar_codigo "the kernel accumulates texture samples" "$SOURCE" 'sum [+]= texture[(]'
# ERE: '(' is literal and '\(' opens a group, so the parenthesis needs a class.
afirmar_codigo "the sampling runs over a neighbourhood" "$SOURCE" 'for [(]int x = -1; x <= 1' 
afirmar_codigo "the result is averaged" "$SOURCE" 'sum /' 

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
afirmar_codigo "derives from OffscreenEffect (which continues the chain)" "$HEADER" 'public[[:space:]]+OffscreenEffect'
# CHANGED IN M1.3a. This used to assert the opposite -- that the effect does NOT
# override drawWindow -- and it was right for M1.2, where the base class did the
# whole job and overriding it was the known cause of two black screens. M1.3a needs
# the override: the desktop has to be captured before the window is painted, and
# drawWindow is the only place with the render target.
#
# The ban was the wrong test, not the override. What protects the screen is the
# property, and that is checked where it can be SHOWN to fail: verify-chain.sh with
# defective sources (tests/test-effect.sh) and the line below.
afirmar_codigo "the effect overrides drawWindow to capture the desktop" "$SOURCE" 'void MacosGlassEffect::drawWindow'
afirmar_codigo "and that override continues the chain" "$SOURCE" 'OffscreenEffect::drawWindow[(]'

# The retired instrument is NOT asserted here any more. `measure-diffusion.py` moved to
# tests/archive/ with test-diffusion.sh: it answered "is local contrast lost with brightness
# preserved" for a design that took its blur from the window's own texture. Asserting that a
# retired tool still exists pins scaffolding, not behaviour.
