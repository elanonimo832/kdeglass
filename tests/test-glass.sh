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

EF="$PROJECT/effect-kwin"
SOURCE="$EF/src/glass.cpp"
HEADER="$EF/src/glass.h"

echo "  -- the title bar is translucent --"
afirmar_codigo "the shader writes a reduced alpha in the band" "$SOURCE" 'uGlassAlpha'
afirmar_codigo "the glass alpha is a named constant" "$HEADER" 'kGlassAlpha'

echo "  -- the content is left alone --"
afirmar_codigo "outside the band the window texel is returned unmodified" "$SOURCE" 'vec4 window = texture[(]sampler, vTexCoord[)]'
afirmar_codigo "and that is exactly what the content path returns" "$SOURCE" 'fragColor = window;'

echo "  -- the scene is told the window is translucent --"
# Setting an alpha in the shader is not enough: the scene blends the redirected
# texture only for a window it considers translucent.
afirmar_codigo "the effect marks the window translucent" "$SOURCE" 'data\.setTranslucent[(][)]'

echo "  -- the DESKTOP is captured, because an alpha cannot invent it --"
# The mechanism limit that made M1.3a measure OPAQUE: the shader's only input was
# the window's own texture, and no alpha puts the desktop into a texture that does
# not contain it. So the desktop is copied out of the screen before the window is
# painted over it.
afirmar_codigo "the background is captured from the render target" "$SOURCE" 'blitFromRenderTarget'
afirmar_codigo "the capture has its own texture and framebuffer" "$SOURCE" 'GLTexture::allocate'
afirmar_codigo "the capture happens before the window is drawn" "$SOURCE" 'captureBackground[(]'
# The override must continue the chain on its only path, or the screen goes black.
afirmar_codigo "the drawWindow override continues the chain" "$SOURCE" 'OffscreenEffect::drawWindow[(]'
# RISK: frameGeometry() of a maximised window is the whole screen, and a window
# dragged past the edge goes outside it. An out-of-bounds blit is undefined
# behaviour, so the source MUST be clamped.
afirmar_codigo "the blit source is clamped to the render target" "$SOURCE" 'intersected[(]'
# Device pixels, not logical ones: at scale != 1 the texture must be larger than
# frameGeometry(). KWin's own transform, not arithmetic done by hand.
afirmar_codigo "the capture is sized in device pixels" "$SOURCE" 'mapToRenderTargetTexture'
# AND it must cover exactly the region KWin redirected: the offscreen texture is
# expandedGeometry()*scale (frame PLUS shadow margins) and the shader's vTexCoord runs
# across all of it. A frame-sized capture samples the desktop shifted by the shadow
# margin -- a bug that would have looked like a uv or flip problem.
afirmar_codigo "the capture covers the EXPANDED geometry KWin redirected" "$SOURCE" 'expandedGeometry[(][)]'
afirmar_codigo "and it is snapped to the device grid the way KWin does" "$SOURCE" 'snapToPixels'
negar "the capture is not framed to frameGeometry" \
  grep -qE 'snapToPixels[(]w->frameGeometry' "$SOURCE"
# The composite happens in the shader, so there is no second quad that could be
# drawn under the window (HANDOFF section 5, risk 4).
afirmar_codigo "the shader samples the captured background" "$SOURCE" 'texture[(]background'
afirmar_codigo "the composite does not depend on the scene blending alpha" "$SOURCE" 'uHasBackground'
afirmar_codigo "the composite keeps part of the bar colour" "$SOURCE" 'mix[(]gained, baseline, uGlassAlpha[)]'
afirmar_codigo "the bar's opacity is tunable too" "$SOURCE" 'GlassAlpha'

echo "  -- the chrome stays readable, and the corners stay round --"
# The user, after the frost landed: "que se vean los botones y el titulo de la ventana".
# The band used to be the BLURRED window texture, so the title and the traffic lights
# were smeared into it. Now the blur is the BASELINE, and what deviates from it is the
# chrome, which is drawn crisp over the glass -- the way macOS does it: the glass is
# behind the chrome, not over it.
afirmar_codigo "the chrome is found by its deviation from the bar's median tone" "$SOURCE" 'abs[(]dot[(]window[.]rgb - baseline'
# The glass carries the bar's TONE, so any chrome left in it is a ghost of the title
# behind the crisp title. A 6 px average keeps ~11 levels of a 2 px stroke; half the
# bar's height keeps ~4, which cannot be seen.
afirmar_codigo "the bar's tone is averaged over the bar's own scale" "$SOURCE" 'max[(]uRadius, uTitleBarHeight [*] 0[.]5[)]'
afirmar_codigo "and it is composited crisp on top of the glass" "$SOURCE" 'mix[(]glass, chromeColour, chrome[)]'
# VIBRANCY, off by default: the theme's title is dark and the frosted backdrop can be
# dark, so with little of the bar's colour kept the title disappears. macOS adapts the
# chrome to the material. It is a setting because it changes the title's colour, which is
# a decision for a screen.
afirmar_codigo "vibrancy is off by default" "$HEADER" 'kVibrancy = 0'
afirmar_codigo "and it is a live setting" "$SOURCE" 'Vibrancy'
afirmar_codigo "it adapts achromatic chrome only, never the coloured buttons" "$SOURCE" 'isColour > 0[.]15'
# 0.15 and not 0.5: the anti-aliased edge of a button is only PARTLY saturated, and at the
# looser threshold vibrancy pushed those edge pixels to ~0.86 of luminance -- measured as a
# light ring of 206-217 around the traffic lights against a band of 117.
# The wiring: the main path must go through the helper, or vibrancy is a function nobody
# calls -- the same trap as the `discard;` that could never run.
afirmar_codigo "and the main path uses it" "$SOURCE" 'chromeWithVibrancy[(]window[.]rgb, glass, chrome, byColour[)]'
# The wiring, not the name: the adaptation must be what gets composited.
afirmar_codigo "and the adapted chrome is the one composited" "$SOURCE" 'mix[(]glass, chromeColour, chrome[)]'
# THE BASELINE MUST BE TIGHT. The first version measured the deviation against the
# 6-texel blur, and a wide average is dragged towards every glyph and button, so the bar
# pixels AROUND them were classified as chrome and drawn crisp: a bright halo around
# each letter and each traffic light, which is what the user saw.
afirmar_codigo "the chrome is measured against the bar's own median tone" "$SOURCE" 'window[.]rgb - baseline'
afirmar_codigo "and its threshold is one tunable knob" "$SOURCE" 'uChromeLow'
# Colour is chrome too. Without this the traffic lights come out as bright rings with
# glass in the middle, because a tight baseline sees the same colour in the centre of a
# 12 px disc as around it. Chroma is local, so it costs no halo.
# ...and it must be USED, not merely declared: asserting the name alone passed while
# the term was disconnected, which is the third time this shape has bitten.
afirmar_codigo "coloured chrome is detected by its chroma, so discs stay solid" "$SOURCE" 'max[(]byCoverage, byColour[)]'
# And the mask is a COVERAGE, not a switch: the theme bakes its own white into every
# anti-aliased boundary pixel, so drawing those "crisp" is a white fringe over our glass. The
# estimated coverage turns a half-covered pixel into half glass.
afirmar_codigo "the chrome weight is an estimated coverage" "$SOURCE" 'clamp[(][(]toneLuma - luma[)] / toneLuma'
# PREMULTIPLIED output: KWin blends with GL_ONE, GL_ONE_MINUS_SRC_ALPHA, so an
# unpremultiplied colour with alpha below 1 ADDS to the backdrop instead of replacing it.
afirmar_codigo "the band's colour is premultiplied by its alpha" "$SOURCE" 'result [*] window[.]a'
# And the corners: this theme's SVG has a 12 px arc but aurorae clips it into a 1 px
# cell, so the frame is a rectangle and there is no shape to follow. The effect draws
# the rounded rectangle itself and discards what falls outside it (0 disables it).
afirmar_codigo "the window's rounded corners are drawn by the effect" "$SOURCE" 'uCornerRadius'
afirmar_codigo "by discarding what falls outside the rounding" "$SOURCE" 'discard;'
# The condition itself, not just the two names: the first version of this assertion was
# satisfied by a `discard;` that never ran, which is the "a check that does not run is
# not a check" lesson in its newest costume.
afirmar_codigo "the discard is the SIGN of the rounded distance" "$SOURCE" 'roundedDistance < 0[.]0'
afirmar_codigo "which is a rounded-box distance at the corners" "$SOURCE" 'length[(]max[(]q, vec2[(]0[.]0[)][)][)] [+] min[(]max[(]q[.]x, q[.]y[)], 0[.]0[)]'
# ...and only for the windows the material covers. A fullscreen window IS the screen:
# rounding it would carve arcs out of the screen and show the desktop through them. A
# client-side decoration is the case this effect leaves alone everywhere else.
afirmar_codigo "only decorated, non-fullscreen windows are rounded" "$SOURCE" 'isNormalWindow[(][)] && w->hasDecoration[(][)] && !w->isFullScreen[(][)]'
# The one orientation that cannot be settled without a screen is a setting, so it
# can be flipped and reconfigured WITHOUT a relogin.
afirmar_codigo "the capture orientation is configurable, not assumed" "$SOURCE" 'BackgroundFlipV'

echo "  -- M1.3a step 3a: the frost over the captured desktop --"
# Step 2 shows the desktop SHARP; macOS shows it frosted. It is a setting so it can be
# tuned without a rebuild, and its default is the kit's own outer radius: 16 is what the
# user's eye selected on screen. 0 is the sharp composite step 2 was verified with, and
# 6 is real but invisible against anything coarser than text.
afirmar_codigo "the frost radius defaults to the kit's outer 16" "$HEADER" 'kBackgroundRadius = 16'
afirmar_codigo "the radius is read from the effect's config" "$SOURCE" 'BackgroundRadius'
afirmar_codigo "the shader can blur the captured background" "$SOURCE" 'uBackgroundRadius'
# The capture is a different texture from the window's, so it has its own texel size.
# Reusing the window's would make the radius a ~3% lie, which is free to avoid.
afirmar_codigo "the frost is measured in the capture's own texels" "$SOURCE" 'uBackgroundTexel'
# Radius 0 must be the SINGLE-sample path, not a stack of samples of the same texel:
# the sharp state has to stay identical to what was verified.
afirmar_codigo "radius 0 keeps the single-sample path" "$SOURCE" 'desktop = texture[(]background, uvFrost[)]'
# TWO SCALES, because one 3x3 at the outer spacing samples nine isolated points and a
# background with text reads as nine ghost copies of it -- seen on screen at radius 16.
# The pair is the kit's `frost 6/16/16`, the outer sampled twice because that is how the
# kit writes it.
afirmar_codigo "the frost samples an inner scale derived from the kit" "$SOURCE" 'kInnerScale'
afirmar_codigo "the frost is a pyramid of four levels" "$SOURCE" 'kLevelScale\[3\] = float\[3\]'

echo "  -- there is a measurement for background show-through --"
afirmar_existe "measure-glass.py exists" "$EF/measure-glass.py"
afirmar_existe "measure-alignment.py exists (step 3d)" "$EF/measure-alignment.py"

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
  malos_shader=$(python3 - "$SOURCE" <<'PYEOF'
import pathlib, re, subprocess, sys, tempfile

text = pathlib.Path(sys.argv[1]).read_text()
shaders = {}
for nombre, var in (("vert", "kDiffusionVertex"), ("frag", "kDiffusionFragment")):
    m = re.search(r'static const char \*' + var + r' = R"\((.*?)\)";', text, re.S)
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

echo "  -- the alignment instrument recovers a known displacement --"
# Step 3d: does the band sample the backdrop where it should, or does the content arrive
# displaced by the decoration's shadow margins (14 px across, 7 px down on this theme)?
# It cannot be answered by looking, because the backdrop BEHIND the window is hidden; the
# instrument compares the band against the same backdrop just OUTSIDE the window, and a
# synthetic image reproduces that exactly, with a displacement chosen by the test.
#
# Written before the tool existed, so it fails on a missing tool instead of passing on
# nothing -- and the displacement is asserted with its SIGN, because a sign error would
# be invisible if only the magnitude were checked.
if ! python3 -c 'import PIL, numpy' >/dev/null 2>&1; then
  ok "(SKIPPED: Pillow/numpy are not installed; the alignment instrument was NOT exercised)"
else
  ALIGN_TMP="$(mktemp -d)"
  python3 - "$ALIGN_TMP" <<'PYEOF'
import pathlib, sys
import numpy as np
from PIL import Image

d = pathlib.Path(sys.argv[1])
rng = np.random.default_rng(7)
HEIGHT, WIDTH = 600, 900
# A backdrop with UNIQUE structure in both axes: random horizontal lines (text) and
# random vertical columns. Periodic structure would give the correlation several equally
# good lags and the test would be measuring the period instead of the displacement.
base = np.full((HEIGHT, WIDTH, 3), 200, dtype=np.uint8)
y = 0
while y < HEIGHT:
    h = int(rng.integers(3, 9))
    base[y:y + h, :] = int(rng.integers(60, 120))
    y += h + int(rng.integers(6, 20))
x = 0
while x < WIDTH:
    w = int(rng.integers(2, 10))
    base[:, x:x + w] = int(rng.integers(120, 170))
    x += w + int(rng.integers(10, 40))

X, Y, W, BAR = 300, 200, 400, 40


def captureLine(dx, dy, plano=False):
    img = np.full((HEIGHT, WIDTH, 3), 180, dtype=np.uint8) if plano else base.copy()
    for j in range(BAR):
        fila = (Y + j + dy)
        for i in range(W):
            col = (X + i + dx)
            if 0 <= fila < HEIGHT and 0 <= col < WIDTH:
                img[Y + j, X + i] = base[fila, col]
    return img


Image.fromarray(captureLine(0, 0)).save(d / "alineado.png")
Image.fromarray(captureLine(14, 7)).save(d / "desplazado.png")
Image.fromarray(captureLine(0, 0, plano=True)).save(d / "plano.png")
PYEOF
  alin=$(python3 "$EF/measure-alignment.py" "$ALIGN_TMP/alineado.png" 300 200 400 40 2>&1)
  despl=$(python3 "$EF/measure-alignment.py" "$ALIGN_TMP/desplazado.png" 300 200 400 40 2>&1)
  plano=$(python3 "$EF/measure-alignment.py" "$ALIGN_TMP/plano.png" 300 200 400 40 2>&1)

  dx_alin=$(printf '%s\n' "$alin" | sed -n 's/^horizontal: *//p' | cut -d' ' -f1)
  dy_alin=$(printf '%s\n' "$alin" | sed -n 's/^vertical: *//p' | cut -d' ' -f1)
  dx_des=$(printf '%s\n' "$despl" | sed -n 's/^horizontal: *//p' | cut -d' ' -f1)
  dy_des=$(printf '%s\n' "$despl" | sed -n 's/^vertical: *//p' | cut -d' ' -f1)

  afirmar_igual "an aligned band reports no displacement" "0 0" "${dx_alin:-?} ${dy_alin:-?}"
  # The band's content was taken from 14 px to the RIGHT and 7 px DOWN, and the instrument
  # reports the displacement in that same direction: positive = the band shows what
  # belongs further right / further down. Measured on the frame 1:1.
  afirmar_igual "a displaced band reports (14, 7), with sign" "14 7" "${dx_des:-?} ${dy_des:-?}"
  if grep -qi 'inconclusive' <<< "$plano"; then
    ok "a flat backdrop is reported inconclusive instead of inventing a shift"
  else
    fallo "a flat backdrop produced a displacement out of nothing"
  fi
  rm -rf "${ALIGN_TMP:?}"
fi

echo "  -- every setting the effect reads is in its documented table --"
# The README lists the keys and their defaults, and four keys were added in one session.
# A table that drifts is worse than no table: it is read INSTEAD of the code. Both
# directions are checked, because both are failures -- a key nobody documented, and a
# documented key the effect no longer reads.
sourceKeys=$(grep -oE 'readEntry\("[A-Za-z]+"' "$SOURCE" | sed 's/readEntry("//; s/"$//' | sort -u)
# The row shape, not just the first cell: the README has another table whose rows also
# start with a backticked word (`bisect`, `macosglass`), and the looser pattern counted the
# identifiers as undocumented settings.
docKeys=$(grep -oE '^\| `[A-Za-z]+` \|' "$EF/README.md" | sed 's/^| `//; s/` |$//' | sort -u)
undocumented=$(comm -23 <(printf '%s\n' "$sourceKeys") <(printf '%s\n' "$docKeys") | tr '\n' ' ')
notRead=$(comm -13 <(printf '%s\n' "$sourceKeys") <(printf '%s\n' "$docKeys") | tr '\n' ' ')
[ -n "$sourceKeys" ] || fallo "no settings found in glass.cpp; the extraction broke"
afirmar_igual "every key the effect reads is documented" "" "${undocumented% }"
afirmar_igual "every documented key is still read by the effect" "" "${notRead% }"

echo "  -- a diagnostic may not flood the journal --"
# The bug this pins, seen in the real journal on 2026-10-14: prePaintWindow incremented
# its counter only while it was below six, and then asked whether the counter was "<= 6".
# Once the counter stopped, that was true on EVERY paint of every window, and the journal
# took thousands of identical lines a second -- destroying the thing a diagnostic exists
# for, exactly when it was needed. A counter that stops incrementing cannot be a gate.
#
# codigo_contiene strips comments, which matters here: the comment that explains the bug
# quotes the buggy expression, and a check that matched it would be checking the prose.
negar "the per-paint diagnostic cannot log on every paint" \
  codigo_contiene "$SOURCE" 'pre <= 6'
afirmar_codigo "the diagnostic uses one gate and one counter" "$SOURCE" 'const bool shouldLog ='

echo "  -- the capture is cached per size, not rebuilt per paint --"
# Two windows of different sizes repainting used to allocate and free a texture and a
# framebuffer twice PER FRAME for as long as both kept repainting (a terminal with a
# blinking cursor next to a video). The note that deferred the fix said to do it once the
# mechanism was verified; the capture measured 73.8 against a threshold of 12, so it is.
afirmar_codigo "the capture lives in a per-size cache" "$HEADER" 'm_captures'
afirmar_codigo "the cache is bounded, so a resizing window cannot grow it forever" "$HEADER" 'kMaxCaptureSlots'
afirmar_codigo "a capture is looked up by size" "$SOURCE" 'm_captures[.]find[(]key[)]'
# And the wiring, which is the check that keeps mattering: apply() must bind the capture
# this paint filled, not one it hopes is current.
afirmar_codigo "apply() binds the capture this paint filled" "$SOURCE" 'm_currentCapture->texture->bind[(][)]'
afirmar_codigo "a failed capture clears it, so no stale texture can be bound" "$SOURCE" 'm_currentCapture = nullptr;'

echo "  -- the live instruments' journal contract still holds --"
# The live scripts measure by READING the effect's journal: test-glass.sh matches
# `capture:`, `refused=N` and looks for the warning phrases; the handoff tells the reader to
# use `frame=`/`barHeight=` for the band's rectangle and to confirm settings with the
# `reconfigure:` line. Rename any of these and a live test measures NOTHING while still
# reporting success -- the worst failure this project knows, and the reason the harness work
# in section 10 exists at all. The list is explicit rather than extracted on purpose: an
# extracted pattern cannot tell a contract from a coincidence.
for frase in "capture: ok=" "refused=" "cannot allocate" "not valid" "failed to load" \
             "blit was refused" "frame=" "barHeight=" "reconfigure:"; do
  afirmar_codigo "the journal still carries '$frase'" "$SOURCE" "$frase"
done

echo "  -- one identifier: the plugin id is the file's name --"
# KWin derives the effect id from the .so's FILE NAME. CMakeLists says so in a comment that
# exists because a `lib` prefix once broke exactly this. So the output name, the file
# install.sh copies and the ID it verifies have to be the same word: any disagreement means
# the effect silently never loads, which is indistinguishable from "the effect does nothing".
id_cmake=$(grep -oE 'OUTPUT_NAME "[A-Za-z0-9_]+"' "$EF/CMakeLists.txt" | sed 's/OUTPUT_NAME "//; s/"$//' | head -1)
id_install=$(sed -n 's/^ID=\(.*\)$/\1/p' "$EF/install.sh" | head -1)
id_copia=$(sed -n 's#^SO="\$HERE/build/plugins/kwin/effects/\(.*\)\.so"$#\1#p' "$EF/install.sh" | head -1)
[ -n "$id_cmake" ] || fallo "no OUTPUT_NAME found in CMakeLists.txt; the extraction broke"
afirmar_igual "the CMake output name and install.sh's ID agree" "$id_cmake" "$id_install"
afirmar_igual "and the file install.sh copies is that same name" "$id_cmake" "$id_copia"

echo "  -- the review's findings stay fixed --"
# The clear must come BEFORE the first early return. Asserting the string alone passed
# while the clear sat after them, which is what a reviewer caught: the comment and the test
# claimed an invariant the code did not hold. So this checks PLACEMENT.
python3 - "$SOURCE" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
body = src.split("MacosGlassEffect::captureBackground", 1)[1].split("\n}\n", 1)[0]
clearAt = body.find("m_currentCapture = nullptr;")
output = body.find("return false;")
print("OK" if 0 <= clearAt < output else "MAL")
PYEOF
if python3 - "$SOURCE" <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
body = src.split("MacosGlassEffect::captureBackground", 1)[1].split("\n}\n", 1)[0]
clearAt = body.find("m_currentCapture = nullptr;")
output = body.find("return false;")
raise SystemExit(0 if 0 <= clearAt < output else 1)
PYEOF
then
  ok "the capture pointer is cleared before any early return"
else
  fallo "m_fondoActual is cleared after an early return, so it can outlive its capture"
fi
# std::map is ordered by KEY, so erase(begin()) evicts the SMALLEST size -- and a small
# terminal is the window this cache exists for. The cap must evict the least recently used.
negar "the cache does not evict by key order" \
  codigo_contiene "$SOURCE" 'm_captures.erase[(]m_captures.begin[(][)][)]'
afirmar_codigo "it evicts the least recently used entry" "$SOURCE" 'm_lastUse\[leastRecentlyUsed->first\]'
# A destination built from the CLAMPED source can be smaller than the texture, and with a
# cache the unwritten strip would hold a PREVIOUS window's capture.
afirmar_codigo "the capture is cleared before the blit" "$SOURCE" 'glClear[(]GL_COLOR_BUFFER_BIT[)]'
# Both paths write premultiplied: the scene blends with GL_ONE, GL_ONE_MINUS_SRC_ALPHA.
afirmar_codigo "the no-capture fallback is premultiplied too" "$SOURCE" 'fallback [*] uGlassAlpha'
# Rounding a window whose frame reaches the screen edge would carve an arc out of the screen.
afirmar_codigo "windows that reach the screen edge are not rounded" "$SOURCE" '&& !m_touchesEdge'
afirmar_codigo "and that is computed where the viewport is" "$SOURCE" 'm_touchesEdge = frameRect.left'
# Vibrancy must DELIVER the minimum contrast, not approach it: aim at a luminance that far
# from the glass and shift, which is exact, instead of mixing towards black or white.
# CHANGED: aiming at the minimum contrast produced a mid-grey glyph on a mid-grey glass,
# which the user read as "borroso o de mala calidad". The chrome is FLIPPED to the far end now,
# which is what macOS does, over a short ramp so a moving backdrop cannot flicker it.
# The two ends are Apple's `[label_vibrant] primary` (#1A1A1A / #F5F5F5), not black and white:
# the user asked whether the light case should be black or a dark grey, and their own tokens
# answer it -- and the VIBRANT group is the right one because it is opaque, unlike `[label]`,
# which is a veil (black at 85%).
afirmar_codigo "vibrancy flips to Apple's vibrant label colours" "$SOURCE" 'kLabelDark = 26[.]0 / 255[.]0'
afirmar_codigo "and its light end" "$SOURCE" 'kLabelLight = 245[.]0 / 255[.]0'
afirmar_codigo "picking by the material's luminance" "$SOURCE" 'backdropLuma > 0[.]5 [?] kLabelDark : kLabelLight'
afirmar_codigo "over a ramp, not an instant jump" "$SOURCE" 'falta = clamp'

echo "  -- the sampling sub-rectangle, ON, decided by arithmetic --"
# The last open question of M1.3a: the capture covers the window's EXPANDED geometry while every
# size the shader uses comes from the FRAME. The user ran both and saw no difference -- correctly,
# because a 16 px frost over a smooth backdrop absorbs a 14 px offset and a 2% scale. The
# arithmetic decides it instead: the corners prove vTexCoord runs across the FRAME, so the capture
# must be sampled at the frame's sub-rectangle, and the identity is a KNOWN offset.
afirmar_codigo "the sub-rectangle switch exists" "$HEADER" 'm_captureSubRect'
afirmar_codigo "and it is ON, because the identity is a known 14 px offset" "$HEADER" 'kCaptureSubRect = true'
afirmar_codigo "with it on the frame's place inside the capture is used" "$SOURCE" \
  'm_captureSubRect [?] m_sampleOffset : QVector2D[(]0[.]0f, 0[.]0f[)]'
afirmar_codigo "the frame's place inside the capture is computed" "$SOURCE" \
  'm_sampleOffset = QVector2D[(]float[(]frameRect[.]x[(][)] - region[.]x[(][)][)]'
afirmar_codigo "the shader applies the offset and scale to the backdrop's uv" "$SOURCE" \
  'uBackgroundOffset [+] vTexCoord [*] uBackgroundScale'

echo "  -- the bar's kernels do not look outside the bar --"
# Measured on the user's screen: the lower 14 rows of a 39-row band had an implied tone of
# 167 where the bar's own is 238 -- exactly (246+246+30)/3, one of the tone kernel's three
# vertical samples inside the client, with a one-row transition because three discrete
# samples make a step and not a gradient. Both kernels over the WINDOW texture are clamped to
# the band now; the kernel over the CAPTURE must NOT be, because the backdrop legitimately
# extends past the bar.
afirmar_codigo "the band's v span is computed" "$SOURCE" 'vBandBottom = 1[.]0 - uTitleBarHeight [*] uTexelSize[.]y'
afirmar_codigo "the tone can only sample inside the bar" "$SOURCE" 'clamp[(]vTexCoord[.]y - toneRadius [*] uTexelSize[.]y, vBandBottom, vBandTop[)]'
afirmar_igual "the backdrop kernel is NOT clamped (the backdrop goes past the bar)" "2" \
  "$(grep -c 'uvFrost + dir' effect-kwin/src/glass.cpp)"

echo "  -- the tone is a median, not a displaced blur --"
# The user's second look, in their own words: "hay como botones fantasma arriba de los
# botones". Measured: the traffic lights sit 20 rows below the bar's top and rows 48..70 of
# the band carried a dark ghost of them, because one sample of the tone's 3x3 had landed on
# the buttons, 19 rows above them -- the radius. A blur of the bar always contains the chrome
# displaced; a median of five discards a minority of it by construction.
afirmar_codigo "the tone takes five samples" "$SOURCE" 'vec4 c4 = texture'
afirmar_codigo "and sorts them channel-wise for the median" "$SOURCE" 'KSORT[(]c0, c1[)]'
afirmar_codigo "the median is what becomes the bar's tone" "$SOURCE" 'vec3 baseline = c2[.]rgb'
# The network itself is pinned: nine compare-exchanges, and the median is the third element.
afirmar_igual "the sorting network is the verified one" "9" \
  "$(grep -o 'KSORT[(]c[0-9], c[0-9][)]' effect-kwin/src/glass.cpp | wc -l)"

echo "  -- the tone's samples go up and down, never sideways --"
# The second look: the buttons clean, the title still doubled. The chrome of this theme is WIDE
# and THIN, so the two samples the first median took along the row landed on it too -- three of
# five -- and the median was chrome. Every sample is vertical now, which is the only direction
# in which the chrome is not there.
afirmar_igual "no tone sample is taken along the row" "0" \
  "$(grep -c 'toneRadius [*] uTexelSize[.]x' effect-kwin/src/glass.cpp)"
afirmar_igual "and all five are vertical" "4" \
  "$(grep -c 'toneRadius [*] uTexelSize[.]y' effect-kwin/src/glass.cpp)"
afirmar_codigo "reaching two radii out" "$SOURCE" '2[.]0 [*] toneRadius [*] uTexelSize[.]y'

echo "  -- the documented defaults are the ones in the code --"
# The table listed keys and defaults, and the keys were checked; the DEFAULTS were not. They
# changed the day Apple's kit was read (GlassAlpha 0.55 -> 0.25, Vibrancy off -> 0.35), which is
# exactly the drift this catches. Keys with no `k<Key>` constant in the header (0 means "derive
# it", false means "off") are skipped on purpose rather than asserted from a third copy.
faltan_defaults=""
for k in $(grep -oE '^\| `[A-Za-z]+` \|' "$EF/README.md" | sed 's/^| `//; s/` |$//'); do
  valor=$(grep -oE "k$k = [0-9.]+" "$EF/src/glass.h" | head -1 | sed "s/k$k = //" | sed 's/\.$//')
  [ -n "$valor" ] || continue
  fila=$(grep -E "^\| \`$k\` \|" "$EF/README.md")
  case "$fila" in *"$valor"*) ;; *) faltan_defaults="$faltan_defaults $k(=$valor)";; esac
done
afirmar_igual "every documented default matches the code" "" "${faltan_defaults# }"

echo "  -- the material's edge and its amplification --"
# From the user's own reading of a macOS Dock: "el dock tiene como un borde, no es directa la
# transparencia, y este toma el color del background pero lo hace mas fuerte". Measured: bright
# bands of 215-236 (top) and 206-218 (bottom) around a middle of 168-190, and a colour that
# tracks the backdrop with a gain of ~1.6 -- which a plain blend cannot produce.
afirmar_codigo "the band has an edge highlight" "$SOURCE" 'float rim = falloff [*] uRim'
afirmar_codigo "and every edge term measures from THAT, not from the box" "$SOURCE" 'float toEdge = roundedDistance'
afirmar_codigo "and the material amplifies the backdrop's chroma" "$SOURCE" 'uMaterialBoost'
afirmar_igual "1.0 is off, so the knob defaults above it" "1" \
  "$(grep -c 'kMaterialBoost = 1[.]20f' effect-kwin/src/glass.h)"

echo "  -- the capture's reduction is capped at two --"
# A GL_LINEAR blit minifying by 2 reads exactly the four texels of each block (a true box); by 4
# it reads four of sixteen and aliases, which is the moire the user saw over large text.
afirmar_codigo "the downsample factor is clamped to 2" "$SOURCE" 'std::clamp[(]m_backgroundDownsample, 1, 2[)]'
afirmar_codigo "and the derived one too" "$SOURCE" 'std::clamp[(]m_backgroundRadius / 8, 1, 2[)]'

echo "  -- the simulator models the shader faithfully --"
# The user asked for a way to stop paying a relogin per idea. This is it, and the maths is only
# worth trusting if it is checked on every run: --self-test compares the model against the two
# cases whose answer is known by definition (alpha 0 is the frosted backdrop, alpha 1 is the
# bar's tone) and against the one pixel the white fringe lives in (a half-covered glyph edge,
# which must come out PARTIAL, not crisp).
afirmar_existe "simulate.py exists (iteration without a relogin)" "$EF/simulate.py"
if timeout 300 python3 "$EF/simulate.py" --self-test >/tmp/sim-selftest.txt 2>&1; then
  ok "the simulator's self-test passes ($(grep -c . /tmp/sim-selftest.txt) lines of evidence)"
else
  fallo "the simulator's self-test FAILED:"; sed 's/^/      /' /tmp/sim-selftest.txt | head -6
fi
# Its knob defaults must come from the header, or a changed default would be simulated wrongly.
afirmar_codigo "the simulator reads its defaults from the effect" "$EF/simulate.py" 'defaults_from_source'

echo "  -- no Spanish identifiers, checked instead of remembered --"
# The language pass renamed 133 identifiers and I relapsed four times afterwards (salida, cromo,
# desdeArriba, amplificado), each time in a patch written from memory. A habit cannot be the check;
# this is the same shape as the file-name scan in test-claims.sh, with a curated word list so it
# cannot fire on English words that merely contain Spanish letters.
sp_words='amplificado|desdeArriba|desdeAbajo|desdeIzquierda|desdeDerecha|alBorde|salida|cromo|fondo|esquina|saturacion|porColor|porDesviacion|tonoRadio|loguear|reducido|encontrado|clave|marco|pantalla|sombra|barra|ventana|ancho|alto|fila|columna|captura|fichero'
malas=$(grep -oE "\b($sp_words)\b" "$SOURCE" "$HEADER" 2>/dev/null | grep -v ':' | sort -u | tr '\n' ' ')
afirmar_igual "the effect's identifiers are English" "" "${malas% }"

echo "  -- the edge bends the backdrop and draws a line of contrast --"
# The user's samples show the edge carrying the backdrop's chroma in a gradient ACROSS the
# boundary (62, 45, 19 over four rows in one; 9 to 31 in another): a displaced copy of what is
# outside, which is refraction. And the bend alone cannot fix their concrete complaint -- a white
# window behind makes the band white, so the boundary vanishes -- which needs a hairline AWAY from
# the backdrop.
afirmar_codigo "the bend is applied to the frost's own uv" "$SOURCE" 'uvFrost = uvBackground [+] inward'
afirmar_codigo "the bend is a knob, from the kit's refraction" "$SOURCE" 'uRefraction'
afirmar_codigo "a hairline goes away from the backdrop, not toward white" "$SOURCE" 'lineFactor = [(]backLuma > 0[.]5[)] [?] 0[.]35 : 1[.]7'
# And it has its OWN strength, independent of Rim: a boundary that is subtle is the problem the
# user reported, and macOS's window border is one you can see -- 52.7 levels away from a white app
# in the simulation of their exact case.
afirmar_codigo "the hairline strength does not depend on Rim" "$SOURCE" 'hair [*] 0[.]35'

echo "  -- the bend is measured in pixels, not in Rim units --"
# The first version multiplied the displacement by `rim`, the band's STRENGTH (0.2), so a six pixel
# bend was 1.2 and the user -- with a striped wallpaper and an eye for exactly this -- reported "no
# veo ningun desplazamiento del color por las orillas". The falloff, 0..1, is what scales it, and
# Rim decides how much of the band is the bend at all. Simulated on a striped backdrop, the fix
# moves edge pixels by up to 157.6 levels.
afirmar_codigo "the displacement scales with the falloff" "$SOURCE" 'uRefraction [*] uBackgroundTexel [*] falloff'
# The bend is no longer blended beside the frost -- it is the frost's own uv, which is why
# frosting the rim costs a fetch LESS and makes the band one material instead of two.
afirmar_codigo "the rim is the same frost, only bent" "$SOURCE" 'uvFrost = uvBackground [+] inward'
afirmar_codigo "and its strength comes from the same falloff" "$SOURCE" 'float rim = falloff [*] uRim'

echo "  -- the gain is tone-mapped, not clipped --"
# "se ve un como cuadro blancoso en la parte central" was the hard clamp: everything above 0.625
# went to flat white, so a bright part of the backdrop became a plateau -- a white square with an
# outline -- while the edges, which mix the RAW backdrop, looked more translucent than the middle.
afirmar_codigo "the gain has a soft knee above mid grey" "$SOURCE" '0[.]5 [+] over / [(]1[.]0 [+] 2[.]0 [*] over[)]'
# The BOUND is a mathematical property, not a string, so it is not asserted here: the first knee
# (over/(1+over)) reached 1.5 and only the measurement caught it. A string test of a formula is a
# test of its spelling.

echo "  -- dispersion: modelled, measured, and judged not worth its cost --"
# The kit's last unimplemented figure. On a GREY high-contrast backdrop the material cannot produce
# colour on its own, so any red-blue separation in the output is the dispersion and nothing else:
# that makes 0.0 levels the control, and it is exactly what the model gives with dispersion off.
if timeout 300 python3 - <<'PY' >/tmp/dispersion.txt 2>&1
import sys; sys.path.insert(0, "effect-kwin")
import numpy as np
import simulate as S
h, w = 70, 520
xx = np.mgrid[0:h, 0:w][1]
gris = (0.5 + 0.45*(np.sin(xx/26.0) > 0)).astype(float)
fondo = np.dstack([gris, gris, gris])
tema = np.full((h, w, 3), 0.93); tema[24:42, 210:320] = 0.15
sep = {}
# SPECULAR OFF: it saturates the edge toward white, and where one channel clips before another the
# clipping itself creates red-blue separation -- a real effect and a different one.
def sep_at(refraction):
    out = S.simulate(tema, fondo, dispersion=0.29, specular=0.0, refraction=refraction,
                     rim_colour_boost=1.0)
    return np.abs(out[1:9, 40:480, 0] - out[1:9, 40:480, 2]).max() * 255
sin = S.simulate(tema, fondo, dispersion=0.0, specular=0.0, rim_colour_boost=1.0)
print(f"sin dispersion {np.abs(sin[1:9,40:480,0]-sin[1:9,40:480,2]).max()*255:.1f}  "
      f"con refraction 6: {sep_at(6.0):.1f}  con refraction 20: {sep_at(20.0):.1f}")
assert np.abs(sin[1:9, 40:480, 0] - sin[1:9, 40:480, 2]).max() == 0, "grey must stay grey"
# THE SCALE IS THE POINT, and getting this wrong once cost a decision: the dispersion is a FRACTION
# of the bend, so its visibility moves with `Refraction`. Measured at the old default of 6 px it was
# 9 levels -- below the perceptible level, and recorded as not worth building -- while at the current
# 20 px it is ~32, which is colour you can see. The invariant is the ratio, not the absolute value.
bajo, alto = sep_at(6.0), sep_at(20.0)
# IT GROWS WITH THE BEND BUT NOT IN PROPORTION, and I asserted the proportion first and was wrong:
# 17.9 at 6 px against 31.9 at 20 px is a factor of 1.8 where the bend grew by 3.3. The bend is
# applied to the frost's uv, so a wider displacement is compressed by the same 16 px frost that
# smooths everything else -- the rule this project keeps meeting from different sides.
assert bajo > 12, f"even a 6 px bend fringes visibly, got {bajo:.1f}"
assert alto > 1.2 * bajo, f"a larger bend must fringe more, got {bajo:.1f} then {alto:.1f}"
assert alto < 2.5 * bajo, f"but not in proportion: the frost compresses it, got {alto / bajo:.2f}x"
PY
then
  ok "the dispersion control is exact and its effect subtle ($(cat /tmp/dispersion.txt))"
else
  fallo "the dispersion model failed:"; sed 's/^/      /' /tmp/dispersion.txt | head -4
fi
# And the reason it is not in the shader, in the code that would have to pay for it.
afirmar_codigo "dispersion costs THREE frosts, which is why it was measured first" "$EF/simulate.py" '1[.]0 [+] dispersion, 1[.]0, 1[.]0 - dispersion'

echo "  -- the capture's geometry is written down where the default lives --"
# A default that encodes arithmetic must carry the arithmetic, or the next session flips it back
# because the user "saw no difference".
#
# AND THIS CHECK IS A DOCUMENTATION CHECK, not a code one: `codigo_contiene` strips comments, which
# is right for code and wrong for prose. I made the same mistake twice -- asserting a phrase that
# lives in a comment and watching it fail as "not found in the CODE" -- so the two kinds are named
# here, and these use plain grep on purpose.
afirmar_igual "the shadow margin is named in the header" "1" \
  "$(grep -c 'shadowMargin' "$HEADER")"
afirmar_igual "and so is the scale drift" "1" \
  "$(grep -c '1415/1387' "$HEADER")"

echo "  -- M1.5: the bright fillet is NARROW and sits ON TOP of the environment's colour --"
# The design changed twice, both times because the user looked at Apple's edge: first it was a broad
# white band that destroyed the environment's colour (6-12 px), and now it is what their sample
# measures -- a band carrying that colour (chroma 57, ~3.5 logical px) AND, inside it, a sharp bright
# neutral rise (196 -> 213 -> 219, chroma 2) about two pixels wide. So this asserts the STRUCTURE,
# not a lift: it must brighten the outermost rows, LOWER their chroma, and be gone a few rows in.
if timeout 300 python3 - <<'PY' >/tmp/fillet.txt 2>&1
import sys; sys.path.insert(0, "effect-kwin")
import numpy as np
import simulate as S
h, w = 60, 520
tema = np.full((h, w, 3), 0.93); tema[20:34, 240:320] = 0.15
fondo = np.zeros((h, w, 3)); fondo[:, :, 2] = 0.70; fondo[:, :, 1] = 0.55; fondo[:, :, 0] = 0.40
cols = slice(40, 220)
def lum(x, y):   return x[y, cols].mean() * 255
def croma(x, y): return (x[y, cols].max(axis=1) - x[y, cols].min(axis=1)).mean() * 255
sin = S.simulate(tema, fondo, specular=0.0)
con = S.simulate(tema, fondo)
print(f"fila 0: sin filo {lum(sin,0):.1f}/{croma(sin,0):.1f}  con filo {lum(con,0):.1f}/{croma(con,0):.1f}"
      f" | fila 4: {lum(sin,4):.1f} vs {lum(con,4):.1f}")
assert S.SPECULAR > 0 and S.SPECULAR_WIDTH <= 3, "the fillet is narrow and part of Apple's edge"
assert lum(con, 0) > lum(sin, 0) + 15, "the fillet must brighten the outermost row"
assert croma(con, 0) < croma(sin, 0) - 5, "and LOWER its chroma: it is bright and neutral"
# It DECAYS rather than vanishing: at 6 px the fillet deliberately reaches further than the 2 px
# version did, and asserting "zero by row 4" would have pinned the old width in place -- which is
# exactly what the stale `SpecularWidth <= 3` assertion did until the suite caught it.
assert (lum(con, 4) - lum(sin, 4)) < 0.4 * (lum(con, 0) - lum(sin, 0)), "and decay inward: a fillet, not a band"
PY
then ok "the fillet brightens, desaturates and is gone by row 4 ($(cat /tmp/fillet.txt))"
else fallo "the fillet structure is wrong:"; sed 's/^/      /' /tmp/fillet.txt | head -4; fi

echo "  -- the simulator's defaults do not depend on where you stand --"
# "src/glass.h" resolved only from effect-kwin/. Run from anywhere else the open failed, the except
# swallowed it, and every knob silently fell back to the hardcoded number beside it -- which cost
# three contradictory measurements before it was found.
afirmar_codigo "the header path is anchored to the file" "$EF/simulate.py" '__file__'
afirmar_codigo "and a header that cannot be read is LOUD" "$EF/simulate.py" 'could not read.*using the hardcoded fallbacks'
desde_raiz=$(python3 -c "import sys; sys.path.insert(0,'$EF'); import simulate as S; print(S.SPECULAR)")
desde_tmp=$(cd /tmp && python3 -c "import sys; sys.path.insert(0,'$EF'); import simulate as S; print(S.SPECULAR)")
afirmar_igual "the same default from any directory" "$desde_raiz" "$desde_tmp"

echo "  -- the edge carries the environment's colour, which is the user's reading of Apple --"
# "en apple no es color fijo, toma del entorno los colores... la linea superior tomo el color
# predominante de la parte inferior de lo que habia bajo el dock". Measured on their sample, the band
# at that edge is a clear blue (chroma 57) where its surroundings are near-grey (chroma 1). Without
# this term the model gave the band a chroma of 35.1 against an interior of 34.2 -- the same colour,
# which is exactly what they were reporting: the edge was NOT carrying the environment.
if timeout 300 python3 - <<'PY' >/tmp/rimcolour.txt 2>&1
import sys; sys.path.insert(0, "effect-kwin")
import numpy as np
import simulate as S
h, w = 60, 500
tema = np.full((h, w, 3), 0.93); tema[20:34, 200:300] = 0.15
fondo = np.zeros((h, w, 3)); fondo[:, :, 2] = 0.82; fondo[:, :, 1] = 0.62; fondo[:, :, 0] = 0.45
def croma(x):
    return (x.max(axis=2) - x.min(axis=2)).mean() * 255
sin = S.simulate(tema, fondo, rim_colour_boost=1.0, specular=0.0)
con = S.simulate(tema, fondo, specular=0.0)
b_sin, i_sin = croma(sin[0:3]), croma(sin[14:26, 60:440])
b_con, i_con = croma(con[0:3]), croma(con[14:26, 60:440])
print(f"sin el termino: banda {b_sin:.1f} interior {i_sin:.1f} | con {S.RIM_COLOUR}: banda {b_con:.1f} interior {i_con:.1f}")
assert abs(b_sin - i_sin) < 3, f"without it the band must match the interior, got {b_sin:.1f} vs {i_sin:.1f}"
assert b_con > 1.2 * i_con, f"with it the band must be clearly more colourful, got {b_con:.1f} vs {i_con:.1f}"
assert abs(i_con - i_sin) < 0.5, "and the middle of the bar must not change"
PY
then ok "the edge carries the environment's colour and the middle does not change ($(cat /tmp/rimcolour.txt))"
else fallo "the edge colour term failed:"; sed 's/^/      /' /tmp/rimcolour.txt | head -4; fi
