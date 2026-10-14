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
afirmar_codigo "outside the band the window texel is returned unmodified" "$FUENTE" 'vec4 window = texture[(]sampler, vTexCoord[)]'
afirmar_codigo "and that is exactly what the content path returns" "$FUENTE" 'fragColor = window;'

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
# AND it must cover exactly the region KWin redirected: the offscreen texture is
# expandedGeometry()*scale (frame PLUS shadow margins) and the shader's vTexCoord runs
# across all of it. A frame-sized capture samples the desktop shifted by the shadow
# margin -- a bug that would have looked like a uv or flip problem.
afirmar_codigo "the capture covers the EXPANDED geometry KWin redirected" "$FUENTE" 'expandedGeometry[(][)]'
afirmar_codigo "and it is snapped to the device grid the way KWin does" "$FUENTE" 'snapToPixels'
negar "the capture is not framed to frameGeometry" \
  grep -qE 'snapToPixels[(]w->frameGeometry' "$FUENTE"
# The composite happens in the shader, so there is no second quad that could be
# drawn under the window (HANDOFF section 5, risk 4).
afirmar_codigo "the shader samples the captured background" "$FUENTE" 'texture[(]background'
afirmar_codigo "the composite does not depend on the scene blending alpha" "$FUENTE" 'uHasBackground'
afirmar_codigo "the composite keeps part of the bar colour" "$FUENTE" 'mix[(]desktop, baseline, uGlassAlpha[)]'
afirmar_codigo "the bar's opacity is tunable too" "$FUENTE" 'GlassAlpha'

echo "  -- the chrome stays readable, and the corners stay round --"
# The user, after the frost landed: "que se vean los botones y el titulo de la ventana".
# The band used to be the BLURRED window texture, so the title and the traffic lights
# were smeared into it. Now the blur is the BASELINE, and what deviates from it is the
# chrome, which is drawn crisp over the glass -- the way macOS does it: the glass is
# behind the chrome, not over it.
afirmar_codigo "the chrome is found by its deviation from a baseline" "$FUENTE" 'abs[(]dot[(]window.rgb - tight'
# The glass carries the bar's TONE, so any chrome left in it is a ghost of the title
# behind the crisp title. A 6 px average keeps ~11 levels of a 2 px stroke; half the
# bar's height keeps ~4, which cannot be seen.
afirmar_codigo "the bar's tone is averaged over the bar's own scale" "$FUENTE" 'max[(]uRadius, uTitleBarHeight [*] 0[.]5[)]'
afirmar_codigo "and it is composited crisp on top of the glass" "$FUENTE" 'mix[(]glass, window.rgb, chrome[)]'
# THE BASELINE MUST BE TIGHT. The first version measured the deviation against the
# 6-texel blur, and a wide average is dragged towards every glyph and button, so the bar
# pixels AROUND them were classified as chrome and drawn crisp: a bright halo around
# each letter and each traffic light, which is what the user saw.
afirmar_codigo "the chrome baseline is its own, narrow radius" "$FUENTE" 'uChromeRadius'
afirmar_codigo "and its threshold is one tunable knob" "$FUENTE" 'uChromeLow'
# PREMULTIPLIED output: KWin blends with GL_ONE, GL_ONE_MINUS_SRC_ALPHA, so an
# unpremultiplied colour with alpha below 1 ADDS to the backdrop instead of replacing it.
afirmar_codigo "the band's colour is premultiplied by its alpha" "$FUENTE" 'salida [*] window[.]a'
# And the corners: this theme's SVG has a 12 px arc but aurorae clips it into a 1 px
# cell, so the frame is a rectangle and there is no shape to follow. The effect draws
# the rounded rectangle itself and discards what falls outside it (0 disables it).
afirmar_codigo "the window's rounded corners are drawn by the effect" "$FUENTE" 'uCornerRadius'
afirmar_codigo "by discarding what falls outside the rounding" "$FUENTE" 'discard;'
# The condition itself, not just the two names: the first version of this assertion was
# satisfied by a `discard;` that never ran, which is the "a check that does not run is
# not a check" lesson in its newest costume.
afirmar_codigo "outside the arc, and only there" "$FUENTE" 'dot[(]esquina, esquina[)] > uCornerRadius [*] uCornerRadius'
# The one orientation that cannot be settled without a screen is a setting, so it
# can be flipped and reconfigured WITHOUT a relogin.
afirmar_codigo "the capture orientation is configurable, not assumed" "$FUENTE" 'BackgroundFlipV'

echo "  -- M1.3a step 3a: the frost over the captured desktop --"
# Step 2 shows the desktop SHARP; macOS shows it frosted. It is a setting so it can be
# tuned without a rebuild, and its default is the kit's own outer radius: 16 is what the
# user's eye selected on screen. 0 is the sharp composite step 2 was verified with, and
# 6 is real but invisible against anything coarser than text.
afirmar_codigo "the frost radius defaults to the kit's outer 16" "$CABECERA" 'kBackgroundRadius = 16'
afirmar_codigo "the radius is read from the effect's config" "$FUENTE" 'BackgroundRadius'
afirmar_codigo "the shader can blur the captured background" "$FUENTE" 'uBackgroundRadius'
# The capture is a different texture from the window's, so it has its own texel size.
# Reusing the window's would make the radius a ~3% lie, which is free to avoid.
afirmar_codigo "the frost is measured in the capture's own texels" "$FUENTE" 'uBackgroundTexel'
# Radius 0 must be the SINGLE-sample path, not a stack of samples of the same texel:
# the sharp state has to stay identical to what was verified.
afirmar_codigo "radius 0 keeps the single-sample path" "$FUENTE" 'desktop = texture[(]background, uvBackground[)]'
# TWO SCALES, because one 3x3 at the outer spacing samples nine isolated points and a
# background with text reads as nine ghost copies of it -- seen on screen at radius 16.
# The pair is the kit's `frost 6/16/16`, the outer sampled twice because that is how the
# kit writes it.
afirmar_codigo "the frost samples an inner scale derived from the kit" "$FUENTE" 'kInnerScale'
afirmar_codigo "and the outer scale carries the kit's repeated figure" "$FUENTE" '2.0 [*] texture'

echo "  -- there is a measurement for background show-through --"
afirmar_existe "measure-glass.py exists" "$EF/measure-glass.py"

echo "  -- the live test refuses to measure a stale install --"
# The trap this closes: the installed .so was still the pre-capture build when the
# guard was written. Relogin without ./install.sh, and the live test would have
# measured the OLD alpha effect -- an OPAQUE that says nothing about the capture and
# would have been read as "the capture does not work". Verifying the object before
# measuring it is rule 4, and the check belongs in the script that does the measuring.
afirmar_codigo "the live glass test compares build against install" "$EF/test-glass.sh" 'cmp -s'
afirmar_codigo "and it aborts instead of measuring the wrong build" "$EF/test-glass.sh" 'ABORTED: the INSTALLED effect is not the build'
afirmar_codigo "the live titlebar test does the same" "$EF/test-titlebar.sh" 'cmp -s'

echo "  -- the shader is validated without a screen --"
# The failure this prevents: a shader that does not compile is INVISIBLE from here.
# loadShader() logs a critical, the effect draws nothing, and the only way to find
# out was to install it, log out, log back in and look -- which is exactly the cost
# every step of M1.3a pays. glslangValidator answers the syntax and type question
# without a session.
#
# It validates the GLSL the effect embeds with THE PREAMBLE KWIN ACTUALLY INJECTS,
# read from KWin 6.7.5's own source rather than invented:
#   ShaderManager::generateCustomShader prepends only the TRAIT_* defines, and
#   GLShader::preprocess prepends the version directive --
#       #version 140              desktop OpenGL, GLSL >= 1.40 (this machine)
#       #version 300 es           plus `precision highp ...` on OpenGL ES 3.0
# Both are checked, because both are paths KWin takes: a shader that compiles on only
# one of them is a portability bug that would never appear here.
#
# What this still cannot prove: that the GL context really reports the version assumed
# above. Everything else about the compile is now the real thing.
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

DEFINES = "\n".join([
    "#define TRAIT_MAP_TEXTURE 1",
    "#define TRAIT_UNIFORM_COLOR 0",
    "#define TRAIT_MODULATE 0",
    "#define TRAIT_ADJUST_SATURATION 0",
    "#define TRAIT_TRANSFORM_COLORSPACE 0",
    "#define TRAIT_MAP_EXTERNAL_TEXTURE 0",
    "#define TRAIT_MAP_MULTI_PLANE_TEXTURE 0",
    "#define TRAIT_ROUNDED_CORNERS 0",
    "#define TRAIT_BORDER 0",
    "#define TRAIT_YUV_CONVERSION 0",
])
PREAMBULOS = {
    "desktop GLSL 140": "#version 140\n" + DEFINES + "\n",
    "OpenGL ES 300": ("#version 300 es\nprecision highp float;\n"
                      "precision highp sampler2D;\nprecision highp sampler3D;\n"
                      + DEFINES + "\n"),
}

problemas = []
if len(shaders) != 2:
    problemas.append(f"only {len(shaders)} of 2 shaders could be extracted from glass.cpp")
for etiqueta, preambulo in PREAMBULOS.items():
    for nombre, src in sorted(shaders.items()):
        with tempfile.TemporaryDirectory() as d:
            ruta = pathlib.Path(d) / f"glass.{nombre}"
            ruta.write_text(preambulo + src)
            r = subprocess.run(["glslangValidator", "-S", nombre, str(ruta)],
                               capture_output=True, text=True)
        if r.returncode != 0:
            problemas.append(f"{nombre} does not compile with the {etiqueta} preamble")
            problemas.extend("   " + l for l in r.stdout.splitlines() if l.strip())
for p in problemas:
    print("      -> " + p)
print(len(problemas))
PYEOF
)
  n="${malos_shader##*$'\n'}"
  if [ "$n" = "0" ]; then
    ok "the shaders compile with KWin's own preambles (desktop GLSL 140 and ES 300)"
  else
    fallo "the embedded shaders do not compile ($n problems)"
    # The compiler's own words, indented: "got 5" on its own sends the reader
    # looking for the reason instead of showing it.
    printf '%s\n' "$malos_shader" | sed '$d' | sed 's/^/      /'
  fi
fi
