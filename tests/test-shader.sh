# M1.1 -- the effect must actually DRAW something.
#
# Until now the effect loaded, joined the paint chain and drew nothing: the
# harness could only assert black=0%, which proves it does not BREAK rendering
# but says nothing about whether it draws.
#
# M1.1 draws a FLAT COLOUR patch in the top-left corner of every normal window.
# That is the smallest thing that proves the GL path works, and it is measurable:
# the harness looks for the exact colour in the screenshot.

echo "  -- the source draws a flat colour with GL --"
FUENTE="$PROY/effect-kwin/src/glass.cpp"
afirmar_existe "glass.cpp exists" "$FUENTE"
# The call must be in CODE, not in a comment (that mistake cost hours once).
afirmar_codigo "paintWindow binds the framebuffer" "$FUENTE" 'framebuffer\(\)'
afirmar_codigo "it uses a scissor region"          "$FUENTE" 'glScissor|Scissor'
afirmar_codigo "it clears with a colour"           "$FUENTE" 'glClearColor|glClear\('
# And it must STILL continue the paint chain: without that, black screen.
afirmar_codigo "it still continues the paint chain" "$FUENTE" '^[[:space:]]*effects->paintWindow\('

echo "  -- the marker colour is a named constant, not a magic number --"
# The constants live in the header, next to the other kit-derived values.
CABECERA="$PROY/effect-kwin/src/glass.h"
afirmar_codigo "the marker colour is a named constant" "$CABECERA" 'kMarker[RrGgBb][[:space:]]*=[[:space:]]*[0-9]'
afirmar_codigo "the marker size is a named constant"   "$CABECERA" 'kMarkerSize[[:space:]]*=[[:space:]]*[0-9]'
# And the drawing code uses them rather than planting raw numbers.
afirmar_codigo "the drawing uses the named colour" "$FUENTE" 'glClearColor\(kMarker' 

echo "  -- no GL call may run before the chain is continued --"
# If the effect returns early without calling the base, the screen goes black.
# We check the base call is present even in the drawing branch by counting: the
# file must have exactly one effects->paintWindow() call on the normal path.
n=$(grep -cE '^[[:space:]]*effects->paintWindow\(' "$FUENTE" 2>/dev/null)
afirmar_igual "exactly one chain call on the normal path" "1" "$n"

echo "  -- the patch is anchored to the window, in the right direction --"
# Two bugs in a row came from here, and neither was visible to a pixel count:
#   1. using frameGeometry() as an offset inside the window (patch went the
#      wrong way when the window moved)
#   2. flipping Y, on the assumption that glScissor's origin is bottom-left.
#      frameGeometry().y() is ALREADY measured from the top of the screen, so
#      the flip inverted the vertical movement. Confirmed on screen: the patch
#      now stays at the window's top-left corner while it moves.
afirmar_codigo "the scissor uses the device position directly" "$FUENTE" 'glScissor\(x, y, size, size\)'
negar "the Y flip is gone" grep -q 'glScissor(x, fbHeight' "$FUENTE"
afirmar_codigo "the window's global geometry is used" "$FUENTE" 'frameGeometry\(\)\.translated'
afirmar_codigo "the paint translation is applied" "$FUENTE" 'data\.xTranslation\(\)'

echo "  -- KWin's own GL state is restored --"
# KWin clips window painting with the scissor test; clobbering it can leave
# artefacts elsewhere. Both the box and the enabled flag are saved and put back.
afirmar_codigo "the previous scissor box is saved" "$FUENTE" 'glGetIntegerv\(GL_SCISSOR_BOX'
afirmar_codigo "the previous scissor box is restored" "$FUENTE" 'glScissor\(previousBox'
afirmar_codigo "the scissor enabled state is restored" "$FUENTE" 'scissorWasEnabled'
