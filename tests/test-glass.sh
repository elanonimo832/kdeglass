# M1.3a -- real glass: the title bar must SHOW THE BACKGROUND, not just blur itself.
#
# What M1.2b verified and is still invisible in practice: the shader blurs the
# WINDOW OWN texture. Blurring a uniform title bar colour returns the same uniform
# colour, so there is nothing to see. The only evidence was that the title text and
# the traffic lights became unreadable -- the user words: "el fondo blanco no me
# deja ver nada, solo lo se por los botones... y el titulo".
#
# macOS does something different: the bar is TRANSLUCENT and shows the desktop
# behind it. That is what makes it read as glass instead of as smudge, and it is
# also what makes refraction, dispersion and the highlight visible at all: without
# a background showing through, every later step is invisible too.

EF="$PROY/effect-kwin"
FUENTE="$EF/src/glass.cpp"
CABECERA="$EF/src/glass.h"

echo "  -- the title bar is translucent --"
afirmar_codigo "the shader writes a reduced alpha in the band" "$FUENTE" 'uGlassAlpha'
afirmar_codigo "the glass alpha is a named constant" "$CABECERA" 'kGlassAlpha'

echo "  -- the content is left alone --"
afirmar_codigo "outside the band the texel is returned unmodified" "$FUENTE" 'fragColor = texture[(]sampler, vTexCoord[)]'

echo "  -- the scene is told the window is translucent --"
# Setting an alpha in the shader is not enough: the scene blends the redirected
# texture only for a window it considers translucent.
afirmar_codigo "the effect marks the window translucent" "$FUENTE" 'data\.setTranslucent[(][)]'

echo "  -- the DESKTOP is captured, because an alpha cannot invent it --"
# The mechanism limit that made M1.3a measure OPAQUE: the shader's only input was
# the window's own texture, and no alpha puts the desktop into a texture that does
# not contain it. So the desktop is copied out of the screen before the window is
# painted over it.
afirmar_codigo "the background is captured from the render target" "$FUENTE" 'blitFromRenderTarget'
afirmar_codigo "the capture has its own texture and framebuffer" "$FUENTE" 'GLTexture::allocate'
afirmar_codigo "the capture happens before the window is drawn" "$FUENTE" 'captureBackground[(]'
# The override must continue the chain on its only path, or the screen goes black.
afirmar_codigo "the drawWindow override continues the chain" "$FUENTE" 'OffscreenEffect::drawWindow[(]'
# RISK: frameGeometry() of a maximised window is the whole screen, and a window
# dragged past the edge goes outside it. An out-of-bounds blit is undefined
# behaviour, so the source MUST be clamped.
afirmar_codigo "the blit source is clamped to the render target" "$FUENTE" 'intersected[(]'
# Device pixels, not logical ones: at scale != 1 the texture must be larger than
# frameGeometry(). KWin's own transform, not arithmetic done by hand.
afirmar_codigo "the capture is sized in device pixels" "$FUENTE" 'mapToRenderTargetTexture'
# The composite happens in the shader, so there is no second quad that could be
# drawn under the window (HANDOFF section 5, risk 4).
afirmar_codigo "the shader samples the captured background" "$FUENTE" 'texture[(]background'
afirmar_codigo "the composite does not depend on the scene blending alpha" "$FUENTE" 'uHasBackground'
afirmar_codigo "the composite keeps part of the bar colour" "$FUENTE" 'mix[(]desktop, barColour, uGlassAlpha[)]'
# The one orientation that cannot be settled without a screen is a setting, so it
# can be flipped and reconfigured WITHOUT a relogin.
afirmar_codigo "the capture orientation is configurable, not assumed" "$FUENTE" 'BackgroundFlipV'

echo "  -- there is a measurement for background show-through --"
afirmar_existe "measure-glass.py exists" "$EF/measure-glass.py"

echo "  -- the shader is validated without a screen --"
# The failure this prevents: a shader that does not compile is INVISIBLE from here.
# loadShader() logs a critical, the effect draws nothing, and the only way to find
# out was to install it, log out, log back in and look -- which is exactly the cost
# every step of M1.3a pays. glslangValidator answers the syntax and type question
# without a session.
#
# It validates the GLSL the effect embeds, with `#version 330 core` prepended:
# KWin prepends its OWN version header at runtime, so this proves the shader body
# is well formed, not that KWin's preamble matches. That limit is written down
# because a check that oversells itself is worse than no check.
if ! command -v glslangValidator >/dev/null 2>&1; then
  ok "(SKIPPED: glslangValidator is not installed; the shaders were NOT validated)"
else
  malos_shader=$(python3 - "$FUENTE" <<'PYEOF'
import pathlib, re, subprocess, sys, tempfile
texto = pathlib.Path(sys.argv[1]).read_text()
shaders = {}
for nombre, var in (("vert", "kDiffusionVertex"), ("frag", "kDiffusionFragment")):
    m = re.search(r'static const char \*' + var + r' = R"\((.*?)\)";', texto, re.S)
    if m:
        shaders[nombre] = m.group(1)
problemas = []
if len(shaders) != 2:
    problemas.append(f"only {len(shaders)} of 2 shaders could be extracted from glass.cpp")
for nombre, src in sorted(shaders.items()):
    with tempfile.TemporaryDirectory() as d:
        ruta = pathlib.Path(d) / f"glass.{nombre}"
        ruta.write_text("#version 330 core\n" + src)
        r = subprocess.run(["glslangValidator", "-S", nombre, str(ruta)],
                           capture_output=True, text=True)
    if r.returncode != 0:
        problemas.append(f"{nombre}: does not compile")
        problemas.extend("   " + l for l in r.stdout.splitlines() if l.strip())
for p in problemas:
    print("      -> " + p)
print(len(problemas))
PYEOF
)
  n="${malos_shader##*$'\n'}"
  if [ "$n" = "0" ]; then
    ok "the embedded vertex and fragment shaders compile"
  else
    fallo "the embedded shaders do not compile ($n problems)"
    # The compiler's own words, indented: "got 5" on its own sends the reader
    # looking for the reason instead of showing it.
    printf '%s\n' "$malos_shader" | sed '$d' | sed 's/^/      /'
  fi
fi
