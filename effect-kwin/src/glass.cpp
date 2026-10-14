#include "glass.h"

#include <KPluginFactory>
#include <QLoggingCategory>
#include <QString>

#include <core/pixelgrid.h>
#include <core/region.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(MacosGlassEffect, "metadata.json",
                              return true;)

// ---------------------------------------------------------------------------
// M1.2 -- the diffusion shader.
//
// A box blur: for every pixel, average the texels in a square around it. That is
// the simplest thing that is genuinely a blur, and it is measurable -- local
// contrast drops while brightness is preserved (see measure-diffusion.py).
//
// Attribute and uniform names are KWin's, not invented:
//   in vec2 position   -- vertex position, set by GLVertexBuffer's VA_Position
//   in vec2 texcoord   -- texture coordinate, VA_TexCoord
//   uniform sampler2D sampler  -- the window's texture
//   uniform vec2 offset        -- a half-texel nudge KWin applies
// Confirmed by reading GLVertexBuffer's interleaved layout in glvertexbuffer.h
// and the uniform names in glshader.cpp.
//
// texcoord is used directly and NOT derived from position: how the texture maps
// onto the window is not guaranteed to be an identity, and assuming it is would
// make the blur sample the wrong places.
// ---------------------------------------------------------------------------
static const char *kDiffusionVertex = R"(
in vec2 position;
in vec2 texcoord;
out vec2 vTexCoord;
uniform mat4 modelViewProjectionMatrix;
uniform vec2 offset;

void main()
{
    vTexCoord = texcoord;
    gl_Position = modelViewProjectionMatrix * vec4(position + offset, 0.0, 1.0);
}
)";

static const char *kDiffusionFragment = R"(
uniform sampler2D sampler;
uniform sampler2D background;
uniform float uRadius;
uniform vec2 uTexelSize;
uniform vec2 uTextureSize;
uniform float uTitleBarHeight;
uniform float uGlassAlpha;
uniform float uHasBackground;
uniform float uBackgroundFlipV;
uniform float uBackgroundRadius;
uniform vec2 uBackgroundTexel;
uniform vec2 uBackgroundOffset;
uniform vec2 uBackgroundScale;
uniform float uChromeLow;
uniform float uCornerRadius;
uniform float uVibrancy;
uniform float uRim;
uniform float uMaterialBoost;
in vec2 vTexCoord;
out vec4 fragColor;

// VIBRANCY: THE CHROME ADAPTS TO THE GLASS. OFF BY DEFAULT (uVibrancy = 0), so a screen
// being verified is unaffected unless it is asked for.
//
// The theme draws the title in a colour chosen for the BAR's own tone (#404040 here), but
// the bar's tone is now the frosted backdrop, which can be dark. With little of the bar's
// own colour kept (a low GlassAlpha) a dark title then sits on a dark glass and vanishes --
// which is what the user saw on a dark background. macOS solves this by adapting the chrome
// to the material; this does the same, and only when the minimum contrast is set above
// zero: ACHROMATIC chrome keeps at least that much contrast against the glass, moving away
// from it. Colour is left alone (the caller says whether it is colour), so the traffic
// lights stay traffic lights.
const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

vec3 chromeWithVibrancy(vec3 chromeColour, vec3 backdrop, float isChrome, float isColour)
{
    // `isColour > 0.15` and not `> 0.5`, and the difference is a halo the user could see. The
    // anti-aliased EDGE of a coloured button is only partly saturated, so at 0.5 those pixels
    // counted as achromatic chrome and vibrancy pushed them to ~0.86 of luminance -- measured
    // on their screenshot as a light ring of 206-217 around the red and yellow traffic lights,
    // against a band of 117 and a theme bar of 246, which is the aiming version's
    // backdrop + 0.35 exactly. Protecting anything with any measurable chroma keeps the
    // buttons' edges blending into the glass, where they belong, while the title (chroma ~0)
    // still gets the contrast it needs.
    if (uVibrancy <= 0.001 || isChrome < 0.5 || isColour > 0.15) {
        return chromeColour;
    }
    float backdropLuma = dot(backdrop, kLuma);
    float chromeLuma = dot(chromeColour, kLuma);
    float contraste = abs(chromeLuma - backdropLuma);
    if (contraste >= uVibrancy) {
        return chromeColour;
    }
    // FLIP THE CHROME; do not aim at the minimum. The third version of this function, and the
    // first two were wrong in opposite directions: mixing by the shortfall overshot and
    // undershot, and then aiming at EXACTLY the minimum contrast produced a MID-GREY glyph on
    // a mid-grey glass -- which the user described by its symptom: "el texto como que es
    // borroso o se ve de mala calidad". A half-shifted glyph has no crispness left, and they
    // were right.
    //
    // macOS does not aim either: it FLIPS the content, near-white on a dark material and
    // near-black on a light one. The ramp is short on purpose -- going to the extreme the
    // instant the threshold is crossed would flicker as a backdrop moves, and a quarter of the
    // threshold is enough to keep the change crisp without the flicker.
    // APPLE'S OWN TWO ENDS, not black and white. `tokens/tokens-colors.toml`,
    // `[label_vibrant] primary`: light = #1A1A1A, dark = #F5F5F5 at alpha 1 -- and the reason
    // it is the VIBRANT group and not `[label]`: the plain label is a veil (black at 85%), the
    // vibrant one is opaque, which is what a material like this needs. The user asked whether
    // the light case should be black "o mas bien creo que apple usa un gris obscuro": they were
    // right, and the exact grey was in their own tokens.
    const float kLabelDark = 26.0 / 255.0;    // #1A1A1A
    const float kLabelLight = 245.0 / 255.0;  // #F5F5F5
    float falta = clamp((uVibrancy - contraste) / max(uVibrancy * 0.25, 0.001), 0.0, 1.0);
    return mix(chromeColour, vec3(backdropLuma > 0.5 ? kLabelDark : kLabelLight), falta);
}

void main()
{
    // THE MATERIAL COVERS THE CHROME, NOT THE CONTENT.
    //
    // Blurring the whole window was verified working and is unusable: it blurs
    // the text you are reading. macOS never does that -- its material covers the
    // title bar, toolbars and sidebars, and the content stays sharp.
    //
    // VERTICAL FLIP, and it was measured rather than assumed.
    //
    // The first version of this shader tested `vTexCoord.y * uTextureSize.y` as
    // the distance from the top of the window. The result was a blurred band at
    // the BOTTOM of every window -- the status bar, about 28 px up from the bottom
    // edge -- which is exactly where a 28 px band lands if vTexCoord.y is 0 at the
    // BOTTOM. The user's screenshot showed it plainly.
    //
    // OffscreenEffect renders the window into a texture whose v axis runs the
    // other way from window coordinates, so the distance from the window's top is
    // (1 - vTexCoord.y). The content sampling is left alone: it already reads the
    // right texel at the right place, so only the band test needed flipping.
    // ROUNDED CORNERS, DRAWN BY US BECAUSE THE DECORATION'S ARE NOT THERE.
    //
    // The theme's SVG does contain a 12 px arc for its top corners, but aurorae draws
    // the corner piece in a cell as narrow as the frame's border, which this theme sets
    // to 1 px -- so the arc is clipped away and the window's frame is a rectangle. That
    // was measured, not assumed: in an effect-off capture the title bar's white starts
    // at the same x on its first row as 15 rows below (a straight edge, no arc), and the
    // pixels outside it are shadow, not rounding.
    //
    // So the shape is ours: a rounded rectangle with uCornerRadius, and `discard` for
    // what falls outside it. Nothing else is touched -- the shadow lives outside the
    // frame and survives. Radius 0 disables it and leaves whatever the theme drew.
    if (uCornerRadius > 0.5) {
        vec2 pos = vTexCoord * uTextureSize;
        vec2 d = min(pos, uTextureSize - pos);
        if (d.x < uCornerRadius && d.y < uCornerRadius) {
            vec2 corner = vec2(uCornerRadius) - d;
            if (dot(corner, corner) > uCornerRadius * uCornerRadius) {
                discard;
            }
        }
    }

    float yPixelsFromTop = (1.0 - vTexCoord.y) * uTextureSize.y;
    vec4 window = texture(sampler, vTexCoord);
    if (yPixelsFromTop > uTitleBarHeight) {
        // The content is returned untouched, alpha included: this effect has no
        // business changing anything outside the chrome.
        fragColor = window;
        return;
    }

    // 9 taps in a 3x3 grid around the pixel, at a distance of uRadius texels.
    // Enough to be a real blur, few enough to stay cheap.
    //
    // WHAT THIS BLUR IS FOR NOW, because it changed. In M1.2 it WAS the material: the
    // band was the window's own texture, softened. In M1.3a the material is the
    // FROSTED BACKDROP, and blurring the bar is not only pointless (a flat colour
    // blurs to itself) but harmful: it smears the title text and the traffic lights,
    // which is precisely what the user reported and asked to have back.
    //
    // So it is no longer the band's colour; it is the band's BASELINE. Averaged over a
    // radius larger than a glyph stroke, it is what the bar would look like without
    // any chrome, and `window - baseline` is therefore the chrome itself.
    // ...AND IT IS AVERAGED OVER THE BAR'S OWN SCALE, not over six pixels. The glass
    // carries this baseline as the bar's colour, so any chrome left in it shows as a
    // GHOST of the title behind the crisp title -- which is what the user saw. A 6 px
    // average keeps about 11 levels of a 2 px stroke; averaging over half the bar's
    // height leaves about 4, which is invisible. `uRadius` stays as a floor, so the kit's
    // frost figure still means something if it is ever set wider than the bar.
    float toneRadius = max(uRadius, uTitleBarHeight * 0.5);
    // THE TONE MUST NOT LOOK BELOW THE BAR, and this is the fix for a strip the user saw on
    // screen. The kernel reaches tens of pixels vertically, and just below the bar sit the
    // theme's white border and then the client's dark content: a sample landing there drags
    // the tone down, and the glass darkens in a sharp band along the bar's bottom edge.
    // Measured on the user's screenshot: the lower 14 rows of a 39-row band had an implied
    // tone of 167 where the bar's own is 238 -- exactly (246+246+30)/3, one sample in the
    // client -- with a one-row transition, because three discrete samples make a step and not
    // a gradient. Clamping the SAMPLED v to the band's own span keeps the tone the bar's.
    // The HORIZONTAL reach is untouched, so the title is still smeared away, which is what
    // the radius is for.
    float vBandBottom = 1.0 - uTitleBarHeight * uTexelSize.y;
    const float vBandTop = 1.0;

    // ...AND IT MUST BE A MEDIAN, NOT A BLUR. A blur of the bar still CONTAINS the chrome,
    // just displaced by the radius, and that is what the user saw next: "botones fantasma
    // arriba de los botones". Measured on their screenshot: the traffic lights sit 20 rows
    // below the bar's top, and rows 48..70 of the band carried a dark ghost of them (minimum
    // 59 against a band of 188) because one of the three samples of a 3x3 had fallen on the
    // buttons -- 19 rows above them, which is exactly the radius. A median of five samples
    // discards a minority of chrome BY CONSTRUCTION: at most the centre can be on a button,
    // and the four at the radius are bar.
    // ...AND THE SAMPLES MUST GO UP AND DOWN, NOT SIDEWAYS. The first median took two of its
    // five samples along the row, and the chrome in this theme is WIDE and THIN: a line of
    // text and a row of three traffic lights both cover it horizontally, so three of the five
    // samples were chrome and the median WAS chrome -- the ghost survived at the title and
    // around the buttons while the buttons themselves came out clean, which is exactly what
    // the user's next two screenshots showed. Vertical samples miss it: the bar's chrome is a
    // few pixels tall and the nearest sample is nineteen away, so up, down and further out are
    // all bar. The clamp keeps them inside the band, which is also what stops the strip at the
    // bar's bottom from coming back.
    vec4 c0 = texture(sampler, vTexCoord);
    vec4 c1 = texture(sampler, vec2(vTexCoord.x,
                                    clamp(vTexCoord.y - toneRadius * uTexelSize.y, vBandBottom, vBandTop)));
    vec4 c2 = texture(sampler, vec2(vTexCoord.x,
                                    clamp(vTexCoord.y + toneRadius * uTexelSize.y, vBandBottom, vBandTop)));
    vec4 c3 = texture(sampler, vec2(vTexCoord.x,
                                    clamp(vTexCoord.y - 2.0 * toneRadius * uTexelSize.y, vBandBottom, vBandTop)));
    vec4 c4 = texture(sampler, vec2(vTexCoord.x,
                                    clamp(vTexCoord.y + 2.0 * toneRadius * uTexelSize.y, vBandBottom, vBandTop)));
    // Sorting network for five elements, nine compare-exchanges, channel-wise, so c2 ends up
    // holding the median. Verified against a Python replica over 20,000 random cases before
    // it went in: a hand-written sorting network that is subtly wrong looks fine and is not.
    vec4 tmp;
#define KSORT(a, b) tmp = min(a, b); b = max(a, b); a = tmp;
    KSORT(c0, c1) KSORT(c3, c4) KSORT(c2, c4) KSORT(c2, c3) KSORT(c1, c4)
    KSORT(c0, c3) KSORT(c0, c2) KSORT(c1, c3) KSORT(c1, c2)
#undef KSORT
    vec3 baseline = c2.rgb;

    // THE CHROME, DRAWN CRISP AND ON TOP OF THE GLASS.
    //
    // macOS keeps the title and the buttons fully readable: the glass is BEHIND the
    // chrome, not over it. The deviation from a baseline is what tells them apart -- a
    // flat bar deviates by nothing, a glyph or a traffic light deviates a lot.
    //
    // THE BASELINE FOR THIS MUST BE TIGHT, and the first version got it wrong by using
    // the 6-texel blur above: a wide average is dragged towards every glyph and every
    // button, so the bar pixels AROUND them deviate too, get classified as chrome, and
    // are drawn crisp -- a bright halo around each letter and each traffic light. The
    // user saw exactly that ("los botones se ven algo extraños"). The first attempt shrank the
    // baseline to a 3x3 at 3 texels, which narrowed the ring but never removed it: a tight
    // average is still MIXED with the chrome. What removes it is measuring against the median
    // tone, below -- see that comment, and the knob that retired with it.
    // THE BASELINE IS THE MEDIAN TONE ITSELF, and that retired a knob and a kernel. A 3x3
    // baseline close to the chrome gets MIXED with it, so the bar pixels beside a glyph or a
    // button deviate from that mixture, get classified as chrome, and are drawn with the
    // theme's white bar -- the halo the user saw as "un circulo debajo de ellos" and as a
    // title that stayed unreadable. Measured on that screenshot: 1140 pixels brighter than
    // the band around the buttons (maximum 255 against a band of 108) and 1812 around the
    // glyphs. The median tone IS "the bar's own colour", which is precisely what the mask
    // needs to measure against: a glyph deviates from it (chrome), a bar pixel beside the
    // glyph does not (no halo), and a traffic light deviates from it (solid).
    //
    // `high` is derived from `low` (3x) so there is ONE knob to turn on a screen.
    float deviation = abs(dot(window.rgb - baseline, vec3(0.2126, 0.7152, 0.0722)));
    float byDeviation = smoothstep(uChromeLow, uChromeLow * 3.0, deviation);

    // COLOUR IS CHROME TOO, and it is the term that keeps the traffic lights SOLID.
    // A tight baseline sees the same colour in the middle of a 12 px disc as around it,
    // so a deviation-only mask hollows the buttons out: a bright ring with glass in the
    // centre. Chroma is a LOCAL property -- no neighbourhood, no halo -- and the bar is
    // neutral (its own figure is #F6F6F6: saturation 0.02), so anything clearly coloured
    // is chrome by itself.
    float chroma = max(max(window.r, window.g), window.b)
                     - min(min(window.r, window.g), window.b);
    float byColour = smoothstep(0.06, 0.15, chroma);
    float chrome = max(byDeviation, byColour);

    // M1.3a -- THE DESKTOP ITSELF, NOT AN ALPHA.
    //
    // Writing uGlassAlpha as the alpha was measured OPAQUE: the shader's only input
    // was the window's own texture, and no alpha can put the desktop into a texture
    // that does not contain it. drawWindow() captures the desktop into `background`
    // before the window is painted, and the desktop is composited HERE, in the shader.
    //
    // The scene's blend is NOT out of the picture, and an earlier version of this
    // comment claimed it was. The output carries `window.a` and is premultiplied, which
    // is what KWin blends with; the shape of the window comes from the clip above rather
    // than from that alpha, so both conventions land in the same place -- but the comment
    // was wrong and the corner bug in section 5 came from believing it.
    //
    // Compositing in the fragment shader also settles the ordering risk in
    // HANDOFF section 5: the band is drawn where the window is drawn, so there is no
    // second quad that could end up under the window.
    if (uHasBackground > 0.5) {
        // WHERE IN THE CAPTURE THIS FRAGMENT SAMPLES, and it is a uniform because the
        // answer is not settled: the capture covers KWin's offscreen texture, which is the
        // window's EXPANDED geometry (frame plus shadow margins), while every size the
        // shader uses comes from the FRAME. If vTexCoord runs across the frame -- which the
        // rounded corners argue for, since arcs built from the frame's box landed on the
        // window's corners -- then the backdrop must be sampled at the frame's
        // sub-rectangle. With `CaptureSubRect` off this is the identity and the sampling is
        // exactly what was verified before; with it on, the sub-rectangle. Measure both with
        // measure-alignment.py: whichever reports (0, 0) is the truth, and the switch exists
        // so that answer costs no extra build.
        vec2 base = uBackgroundOffset + vTexCoord * uBackgroundScale;
        // uBackgroundFlipV is 1.0 when the capture's v axis disagrees with the window
        // texture's. The default (0) is settled from KWin's own blit code -- both textures
        // are bottom-up -- and the knob is kept for a rotated output, where the blit takes a
        // different branch. See glass.h. It flips the RESULT, so it composes with the
        // sub-rectangle instead of fighting it.
        vec2 uvBackground = vec2(base.x, mix(base.y, 1.0 - base.y, uBackgroundFlipV));

        // STEP 3a -- FROST. The offsets are in SCREEN pixels (uBackgroundTexel is the
        // texel of the full-size region, not of the reduced texture), and the capture is
        // already reduced, so nine taps land on PRE-SMOOTHED values rather than on nine
        // isolated points of text. Pre-smoothed, not averaged: GL minifies with bilinear
        // filtering, which reads a 2x2 neighbourhood and not the whole block -- the honest
        // version of the claim is in captureBackground, and this comment used to oversell
        // it.
        //
        // THE FROST IS TWO SCALES, and that is the kit's own figure: frost 6/16/16 is
        // an inner radius of 6 and an outer of 16, with the 16 repeated. A single 3x3
        // at the outer spacing samples nine ISOLATED points, so a background with text
        // reads as nine ghost copies of it -- measured on screen at radius 16, and the
        // reason this is not one 3x3 any more. Two nested 3x3 grids fill the gaps:
        //     outer 16, twice (the kit repeats it)  -> 18 samples
        //     inner  6 = 16 * 0.375                ->  9 samples
        //     total 27, so the average is /27.
        // Radius 0 takes the branch below and stays bit-identical to the single-sample
        // composite that step 2 was verified with.
        const float kInnerScale = 0.375;   // kit: frost 6/16/16 -> 6 / 16
        vec3 desktop;
        if (uBackgroundRadius > 0.5) {
            vec4 frostSum = vec4(0.0);
            for (int x = -1; x <= 1; ++x) {
                for (int y = -1; y <= 1; ++y) {
                    vec2 dir = vec2(float(x), float(y)) * uBackgroundTexel;
                    frostSum += 2.0 * texture(background, uvBackground + dir * uBackgroundRadius);
                    frostSum += texture(background, uvBackground + dir * uBackgroundRadius * kInnerScale);
                }
            }
            desktop = (frostSum / 27.0).rgb;
        } else {
            desktop = texture(background, uvBackground).rgb;
        }

        // APPLE'S MATERIAL DOES NOT VEIL THE BACKDROP, IT AMPLIFIES IT. Measured on the user's
        // own macOS Dock sample, over two different parts of the wallpaper: the dock's colour
        // tracks the backdrop with a gain of about 1.6, which a plain `a*colour + (1-a)*fondo`
        // cannot produce -- it would need (1-a) = 1.6, greater than one. That is why a
        // quarter-opaque veil looks like grey plastic next to Apple's glass. This is that gain,
        // applied to the chroma around the frosted backdrop's own luminance, so the material
        // keeps the backdrop's colour and makes it stronger instead of washing it out.
        // 1.0 is off; the measured Apple value is 1.6.
        if (uMaterialBoost > 1.001) {
            float luma = dot(desktop, kLuma);
            desktop = clamp(vec3(luma) + (desktop - vec3(luma)) * uMaterialBoost, 0.0, 1.0);
        }

        // The bar keeps uGlassAlpha of its own colour -- its BASELINE, so the chrome is
        // not smeared into the glass -- and lets the frosted backdrop through.
        vec3 glass = mix(desktop, baseline, uGlassAlpha);

        // Vibrancy, off by default; the full explanation is on chromeWithVibrancy above and
        // on the m_vibrancy member in glass.h. This used to be a third copy of it.
        vec3 chromeColour = chromeWithVibrancy(window.rgb, glass, chrome, byColour);

        // PREMULTIPLIED, because that is the convention KWin blends with
        // (GL_ONE, GL_ONE_MINUS_SRC_ALPHA in OffscreenData::paint). Writing an
        // unpremultiplied colour with an alpha below 1 adds it to the backdrop instead
        // of replacing it -- which is what made the first attempt at the corners paint
        // a BRIGHT square instead of nothing. With alpha 1 inside the frame this is
        // identical to what was verified, and the shape now comes from the clip above.
        vec3 result = mix(glass, chromeColour, chrome);

        // THE RIM. Apple's material does not simply end: it has a bright edge. Measured on the
        // user's Dock sample, bright bands of 215-236 along the top and 206-218 along the bottom
        // around a darker middle of 168-190 -- which is what they saw and asked for ("el dock
        // tiene como un borde"). The band's four edges are all known here: the top and the sides
        // from the frame's own rectangle, and the bottom from the title bar's height, where the
        // hairline goes that macOS draws between the bar and the content.
        float fromTop = (1.0 - vTexCoord.y) * uTextureSize.y;
        float fromBottom = uTitleBarHeight - fromTop;
        float fromLeft = vTexCoord.x * uTextureSize.x;
        float fromRight = uTextureSize.x - fromLeft;
        float toEdge = min(min(fromTop, fromBottom), min(fromLeft, fromRight));
        float rim = (1.0 - smoothstep(0.0, 2.0, toEdge)) * uRim;
        result = mix(result, vec3(1.0), rim);
        fragColor = vec4(result * window.a, window.a);
        return;
    }

    // No capture available -- no framebuffer to read, blits unsupported, or the window is
    // off screen. Keep the previous behaviour rather than sample a texture that was never
    // filled: the bar's own tone with an alpha, and the chrome crisp on top of it, with
    // vibrancy applied here too so the two paths do not disagree about the chrome.
    //
    // BOTH PATHS WRITE PREMULTIPLIED, and an earlier version of this comment told a
    // different story here -- that the alpha-only attempt measuring OPAQUE suggested the
    // scene ignores this texture's alpha, so this path could write an UNPREMULTIPLIED
    // colour. Two reviews flagged it, and they are right that the two claims cannot both
    // stand: prePaintWindow asks for translucency and OffscreenData::paint blends with
    // GL_ONE, GL_ONE_MINUS_SRC_ALPHA, so an unpremultiplied colour with an alpha below 1 is
    // ADDED to the backdrop rather than composited over it. The old measurement is left as
    // an unexplained anomaly instead of being used to justify a different convention. The
    // residual risk is the other way: if the alpha really were ignored, this path would be
    // darker rather than brighter -- and it only runs when the capture is unavailable.
    vec3 fallbackChrome = chromeWithVibrancy(window.rgb, baseline, chrome, byColour);
    vec3 fallback = mix(baseline, fallbackChrome, chrome);
    fragColor = vec4(fallback * uGlassAlpha, uGlassAlpha);
}
)";

MacosGlassEffect::MacosGlassEffect()
{
    qInfo() << "[macos-glass] M1.2 loaded. frost radius" << kFrostRadius;

    connect(effects, &EffectsHandler::windowAdded, this, &MacosGlassEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &MacosGlassEffect::slotWindowDeleted);

    const auto windows = effects->stackingOrder();
    for (EffectWindow *w : windows) {
        slotWindowAdded(w);
    }

    effects->addRepaintFull();
}

// The destructor is defaulted ON PURPOSE, and it is safe, which was checked rather than
// assumed. KWin's own Effect documentation (/usr/include/kwin/effect/effect.h, "OpenGL")
// says the framework ensures the OpenGL context is current when the Effect gets created,
// destroyed or reconfigured, and during the painting stages. A current context is what
// GLFramebuffer's destructor needs before it will delete anything, and the journal has
// never carried its "no current context" warning. An earlier version of the handoff listed
// this as a leak to fix, from assuming the opposite -- and the fix it proposed (making the
// capture per window) would have been a lot of work for nothing.
MacosGlassEffect::~MacosGlassEffect() = default;

bool MacosGlassEffect::supported()
{
    // A shader-based effect needs OpenGL. Declaring support unconditionally would
    // make KWin load it on a software compositor and fail to draw.
    return effects->isOpenGLCompositing();
}

void MacosGlassEffect::reconfigure(ReconfigureFlags)
{
    // Read the settings. KWin gives effects their own config group, so these can be
    // changed without a rebuild:
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key BackgroundRadius 16
    //   qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2
    //
    // THE SECOND COMMAND IS THE ONE THAT WORKS, and this comment used to give
    // `qdbus6 org.kde.KWin /KWin reconfigure`, which does NOT reach the effects:
    //   - DBusInterface::reconfigure() -> Workspace::slotReconfigure(), which calls
    //     reparseConfiguration() and touches windows and rules -- but never
    //     effects->reconfigureEffects();
    //   - EffectsHandler::configChanged() only reacts to the [Plugins] group, so
    //     changing [Effect-*] notifies nobody;
    //   - EffectsHandler::reconfigureEffect(name) -- the D-Bus method above -- DOES
    //     call reparseConfiguration() and then this function.
    // Cost of the wrong command: a whole session in which a value was written,
    // "reconfigured", and never read. The log line below is what makes it visible.
    const KConfigGroup cfg = effects->config()->group(QStringLiteral("Effect-macosglass2"));
    m_frostRadius = cfg.readEntry("FrostRadius", kFrostRadius);

    // Only one of the two textures' orientations is unknown until it is seen on a
    // screen, so it is a setting rather than a guess baked into the source: if the
    // band shows the desktop upside down, flip it and reconfigure. No relogin.
    m_backgroundFlipV = cfg.readEntry("BackgroundFlipV", false);

    // The frost over the captured desktop, 0 by default: the first relogin verifies
    // the sharp composite, and this turns the blur on in the same session. See
    // glass.h for why a blur does not disturb the step-2 measurement (it preserves
    // the band's mean, which is what measure-glass.py compares).
    m_backgroundRadius = cfg.readEntry("BackgroundRadius", kBackgroundRadius);

    // 0 = derive it from the radius (radius/4). A positive value is the reduction factor
    // the backdrop is captured at, which is what makes the frost an average instead of a
    // sample. Bigger = smoother and blurrier, and it costs nothing to try.
    m_backgroundDownsample = cfg.readEntry("FrostDownsample", 0);

    // Sample the capture at the FRAME's sub-rectangle. Off until the alignment instrument
    // says which of the two readings is true; see the uniform's comment in the shader.
    m_captureSubRect = cfg.readEntry("CaptureSubRect", kCaptureSubRect);

    // How much of the bar's own colour stays. Not a readability knob any more -- the
    // chrome is drawn crisp on top -- so it is free to go lower for more glass.
    m_glassAlpha = float(cfg.readEntry("GlassAlpha", double(kGlassAlpha)));

    // The chrome mask: how wide its baseline is, and how much deviation counts.
    m_chromeLow = float(cfg.readEntry("ChromeLow", double(kChromeLow)));

    // The window's rounded corners. The theme's own arc does not survive aurorae's
    // 1 px corner cells, so this is drawn here; 0 restores whatever the theme drew.
    m_cornerRadius = cfg.readEntry("CornerRadius", kCornerRadius);

    // Vibrancy, off unless asked for: the chrome's minimum contrast against the glass.
    m_vibrancy = float(cfg.readEntry("Vibrancy", double(kVibrancy)));

    // The material's edge highlight and its amplification of the backdrop; see the shader.
    m_rim = float(cfg.readEntry("Rim", double(kRim)));
    m_materialBoost = float(cfg.readEntry("MaterialBoost", double(kMaterialBoost)));

    qInfo() << "[macos-glass] reconfigure: frostRadius=" << m_frostRadius
            << "backgroundFlipV=" << m_backgroundFlipV
            << "backgroundRadius=" << m_backgroundRadius
            << "frostDownsample=" << m_backgroundDownsample
            << "captureSubRect=" << m_captureSubRect
            << "glassAlpha=" << m_glassAlpha
            << "chromeLow=" << m_chromeLow
            << "cornerRadius=" << m_cornerRadius
            << "vibrancy=" << m_vibrancy
            << "rim=" << m_rim
            << "materialBoost=" << m_materialBoost;

    m_shader.reset();
    loadShader();
    if (m_active) {
        const auto windows = effects->stackingOrder();
        for (EffectWindow *w : windows) {
            redirect(w);
        }
    }

    // ASK FOR A FULL REPAINT, or the new values arrive only where a window happens to
    // be damaged. That is what "the effect improves little by little" was: the band had
    // the old appearance everywhere except the parts that were redrawn, and nothing
    // told the screen to redraw all of it. Note that redirect() is a no-op for windows
    // that are already redirected, so it does not repaint anything either.
    effects->addRepaintFull();
}

bool MacosGlassEffect::loadShader()
{
    if (m_shader) {
        return true;
    }
    // MapTexture: the shader receives the window's texture, which is what a
    // diffusion pass reads from.
    m_shader = ShaderManager::instance()->generateCustomShader(
        ShaderTrait::MapTexture,
        QByteArray(kDiffusionVertex),
        QByteArray(kDiffusionFragment));
    if (!m_shader) {
        qCritical() << "[macos-glass] the diffusion shader failed to load";
        return false;
    }
    return true;
}

void MacosGlassEffect::slotWindowAdded(EffectWindow *w)
{
    // DIAGNOSE: report every decision, so a silent no-op can be told apart from a
    // blur that is too subtle. The first M1.2 attempt produced no visible change
    // and no error, which is exactly the ambiguous case.
    static int logged = 0;
    const bool normal = w->isNormalWindow();

    if (!m_active || !normal) {
        if (logged < 8) {
            ++logged;
            qInfo() << "[macos-glass] DIAGNOSE skip" << w->caption()
                    << "active=" << m_active << "normal=" << normal;
        }
        return;
    }
    if (!loadShader()) {
        qInfo() << "[macos-glass] DIAGNOSE shader FAILED to load";
        return;
    }
    if (logged < 8) {
        ++logged;
        const QSize sz = w->frameGeometry().size().toSize();
        qInfo() << "[macos-glass] DIAGNOSE redirect" << w->caption()
                << "frameSize=" << sz
                << "texel=" << QVector2D(1.0f / (sz.width() ? sz.width() : 1),
                                         1.0f / (sz.height() ? sz.height() : 1));
    }
    // redirect() is what makes KWin render this window into an offscreen texture
    // so the shader can read it.
    redirect(w);
    qInfo() << "[macos-glass] REDIRECT" << w->caption().left(20);
    setShader(w, m_shader.get());

    // Tell the shader how big a texel is, so `uRadius` is expressed in texels
    // rather than in a normalised unit whose meaning changes with window size.
    //
    // CRITICAL: the shader must be BOUND while the uniforms are set.
    // GLShader::setUniform() is just glUniform1f(), which writes to whichever
    // program is currently active. Called without binding, it writes into some
    // other program and our uniforms stay at their default of zero -- and a blur
    // radius of zero makes all nine taps sample the SAME texel, so the average is
    // the original image and nothing changes on screen. That is exactly what was
    // measured: the mechanism ran, the shader was applied, and the picture was
    // identical. pushShader/popShader bind and restore.
    //
    // NOTE: this uses the logical frame size. On a display with scale != 1 the
    // offscreen texture is larger by that factor, so the blur would be
    // proportionally smaller than intended. The output here is scale 1, so it is
    // exact; making it scale-aware is a refinement for when one exists.
    const QSize size = w->frameGeometry().size().toSize();
    if (size.width() > 0 && size.height() > 0) {
        // The title bar height, measured rather than assumed: it is the distance
        // from the top of the frame to the top of the client area. This works for
        // ANY decoration theme, where a hard-coded value would only suit ours.
        // Measured on the KdeMacOS theme: 28 logical pixels.
        qreal barHeight = 0.0;
        if (w->hasDecoration()) {
            barHeight = w->clientGeometry().top() - w->frameGeometry().top();
        }
        // A window with client-side decoration (Zen Browser, most Electron apps)
        // reports frameGeometry() == clientGeometry(), so the difference is zero
        // and there is nothing to cover. KWin does not expose that region, so it
        // cannot be located without guessing -- and a guess was TRIED and removed:
        // it blurred a band on Zen Browser that the user did not want, on a window
        // whose own title bar cannot be measured. Better to do nothing than to
        // blur content on a guess.

        // The uniforms are NOT set here. The shader is a SINGLE object shared by
        // every window, so writing per-window values at add time means the last
        // window to be added wins: uTitleBarHeight would hold another window's
        // bar height, and every focus change would overwrite it. That is why the
        // material flickered away and came back when switching windows.
        // They are set in apply(), which runs per window on every paint.

        static int loggedBar = 0;
        if (loggedBar < 6) {
            ++loggedBar;
            // expanded= and shadowMargin= are here because they are the numbers the
            // material's geometry depends on and they CANNOT be reasoned out: the
            // redirected texture is expandedGeometry()*scale, so every size the
            // shader uses is only exact if the decoration's shadow margins are zero.
            // This theme sets Shadow=true and ships no shadow.svg, which may or may
            // not mean "no shadow" -- so it is logged, not assumed. (The capture line
            // logs the texture size too, so the two together settle it either way.)
            const RectF expandido = w->expandedGeometry();
            const RectF frameRect = w->frameGeometry();
            qInfo() << "[macos-glass] title bar band:" << w->caption()
                    << "frame=" << frameRect
                    << "client=" << w->clientGeometry()
                    << "expanded=" << expandido
                    << "shadowMargin=" << QPointF(frameRect.x() - expandido.x(),
                                                  frameRect.y() - expandido.y())
                    << "barHeight=" << barHeight;
        }
    }
}

void MacosGlassEffect::slotWindowDeleted(EffectWindow *w)
{
    qInfo() << "[macos-glass] UNREDIRECT (window deleted)" << w->caption().left(20);
    unredirect(w);
}

bool MacosGlassEffect::captureBackground(const RenderTarget &renderTarget,
                                         const RenderViewport &viewport, EffectWindow *w)
{
    // CLEARED FIRST, BEFORE ANY EARLY RETURN. It used to be cleared after them, so on the
    // paths that return early the previous window's pointer survived -- harmless only
    // because m_hasBackground is set false by the same failing call. A review pointed out
    // that the comment and the test claimed "at the start of every capture" and the code
    // did not deliver it; now it does.
    m_currentCapture = nullptr;
    if (!m_active || !w->isNormalWindow() || !w->hasDecoration()) {
        return false;
    }
    // No shader means apply() returns before drawing the band, so a capture would be
    // work whose result nobody reads.
    if (!m_shader) {
        return false;
    }
    // Reading from a QImage render target is not possible with a framebuffer blit.
    GLFramebuffer *sourceFbo = renderTarget.framebuffer();
    if (!sourceFbo) {
        return false;
    }
    // CAPTURE THE **EXPANDED** GEOMETRY, NOT THE FRAME, and this is not a detail.
    //
    // KWin redirects the window into a texture of expandedGeometry() * scale
    // (offscreeneffect.cpp, OffscreenData::maybeRender) -- the frame PLUS the
    // decoration's shadow margins -- and the shader's vTexCoord runs 0..1 across
    // that whole texture. Capturing only the frame would therefore map a frame-sized
    // texture onto expanded-sized coordinates: the desktop would be sampled shifted
    // by the top/left shadow margin and scaled by expanded/frame. The band would show
    // the wrong part of the background, and it would look like a uv or flip bug.
    //
    // snapToPixels is KWin's own rounding to the device grid, the same call
    // maybeRender uses, so the captured region is the texture's region and not
    // approximately it.
    const Rect region = snapToPixels(w->expandedGeometry(), viewport.scale()).toRect();
    if (region.isEmpty()) {
        return false;
    }

    // RISK, handled rather than hoped for: expandedGeometry() of a MAXIMISED window is
    // the whole screen plus its shadow, and a window dragged past the edge goes
    // outside it. A blit with an out-of-bounds source is undefined behaviour, so the
    // source is clamped to the render target's logical rect. What is left of the
    // destination is then offset by the same amount, which is why the two are
    // computed separately.
    const Rect source = region.intersected(viewport.renderRect().toRect());
    if (source.isEmpty()) {
        return false;
    }

    // DEVICE pixels, not logical ones: at scale != 1 the texture must be larger than
    // the logical geometry. mapToRenderTargetTexture is KWin's own
    // logical-to-texture transform, so this is not arithmetic done by hand.
    const Rect regionDevice = viewport.mapToRenderTargetTexture(region);
    const QSize size = regionDevice.size();
    if (size.isEmpty()) {
        return false;
    }

    // THE CAPTURE IS TAKEN ALREADY REDUCED, and that is the frost, not an optimisation.
    //
    // Nine samples 16 px apart do not AVERAGE the backdrop, they SAMPLE it: text behind
    // the window stayed recognisable as text, with ghost copies of itself, which is what
    // the user saw on a busy wallpaper. Blurring properly needs samples every pixel or
    // so over the whole footprint, which is hundreds of fetches.
    //
    // The cheap way is the one KWin's own blur uses: reduce first. The blit can scale
    // (its header says so, and the filter argument is GL_LINEAR), so the texture is
    // allocated at region/factor and the blit copies the whole region into it.
    //
    // WHAT THAT ACTUALLY BUYS, without overselling it: glBlitFramebuffer with GL_LINEAR
    // minifies with BILINEAR filtering, which reads a 2x2 neighbourhood of the source --
    // it does NOT box-average the whole factor x factor block, so it is a pre-smoothing
    // and not a true average. That is still the difference between "sampling text" and
    // "sampling a blurred version of text", which is what the user saw, and it costs one
    // blit. A true average would mean averaging the block in the shader, i.e. factor^2
    // more fetches per tap, and the eye has not asked for it yet.
    const int factor = m_backgroundDownsample > 0
        ? m_backgroundDownsample
        : std::clamp(m_backgroundRadius / 4, 1, 16);
    const QSize reducedSize(std::max(1, size.width() / factor),
                         std::max(1, size.height() / factor));

    // Looked up, not rebuilt: two windows of different sizes used to allocate and free a
    // texture and a framebuffer twice per frame for as long as both kept repainting.
    const auto key = std::make_pair(reducedSize.width(), reducedSize.height());
    auto slot = m_captures.find(key);
    if (slot == m_captures.end()) {
        auto newSlot = std::make_unique<CaptureSlot>();
        newSlot->texture = GLTexture::allocate(GL_RGBA8, reducedSize);
        if (!newSlot->texture) {
            qWarning() << "[macos-glass] cannot allocate the capture texture" << reducedSize;
            return false;
        }
        newSlot->texture->setFilter(GL_LINEAR);
        newSlot->texture->setWrapMode(GL_CLAMP_TO_EDGE);
        newSlot->fbo = std::make_unique<GLFramebuffer>(newSlot->texture.get());
        if (!newSlot->fbo->valid()) {
            qWarning() << "[macos-glass] the capture framebuffer is not valid";
            return false;
        }
        // Bounded on purpose, and evicting the LEAST RECENTLY USED, not the first in the
        // map. A review caught the first version: `std::map` is ordered by key, so
        // `erase(begin())` evicted the SMALLEST size -- and a small terminal is exactly the
        // window whose repaints this cache exists to make cheap, so with five or more
        // distinct sizes in a session the thrash came back for the case that motivated the
        // cache. `m_lastUse` is the stamp of the last capture that used an entry.
        if (int(m_captures.size()) >= kMaxCaptureSlots) {
            auto leastRecentlyUsed = m_captures.begin();
            for (auto it = m_captures.begin(); it != m_captures.end(); ++it) {
                if (m_lastUse[it->first] < m_lastUse[leastRecentlyUsed->first]) {
                    leastRecentlyUsed = it;
                }
            }
            m_lastUse.erase(leastRecentlyUsed->first);
            m_captures.erase(leastRecentlyUsed);
        }
        slot = m_captures.emplace(key, std::move(newSlot)).first;
        qInfo() << "[macos-glass] capture texture" << reducedSize
                << "(1/" << factor << "de" << size << ") for" << w->caption().left(20)
                << "-- cached:" << int(m_captures.size());
    }
    m_currentCapture = slot->second.get();
    // WHERE THE FRAME LIES INSIDE THE CAPTURE, as normalized coordinates of the texture.
    // Computed from LOGICAL geometry: the device scale cancels in a ratio, and this is the
    // only place with both rectangles in hand. The texture covers the UNCLAMPED region --
    // the blit writes only the clamped part and the rest is cleared -- so the comparison is
    // against `region`, not against `source`.
    const Rect frameRect = w->frameGeometry().toRect();
    m_sampleOffset = QVector2D(float(frameRect.x() - region.x()) / region.width(),
                               float(frameRect.y() - region.y()) / region.height());
    m_sampleScale = QVector2D(float(frameRect.width()) / region.width(),
                              float(frameRect.height()) / region.height());
    m_lastUse[key] = ++m_useClock;
    m_captureRegion = size;

    const Rect sourceDevice = viewport.mapToRenderTargetTexture(source);
    const Rect completo(sourceDevice.topLeft() - regionDevice.topLeft(), sourceDevice.size());
    // The destination is at the SAME reduced scale, so the blit averages the block.
    const Rect destination(QPoint(completo.x() / factor, completo.y() / factor),
                           QSize(std::max(1, completo.width() / factor),
                                 std::max(1, completo.height() / factor)));

    // blitFromFramebuffer reads from the CURRENT framebuffer. It already is the
    // source while the scene is drawn; pushing it says so instead of assuming it.
    // CLEARED BEFORE THE BLIT, and it is not hygiene. The destination can be SMALLER than
    // the texture: `reducedSize` is floor(size/factor) while `destination` is built from the
    // CLAMPED source, so for a window that extends off screen a strip of the texture stays
    // unwritten -- and with the cache that strip holds a PREVIOUS window's capture, which
    // the frost kernel would blend in at the edge. Clearing makes it transparent black,
    // which the block also is: that strip is the part of the frame that is off screen.
    GLFramebuffer::pushFramebuffer(m_currentCapture->fbo.get());
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    GLFramebuffer::popFramebuffer();

    GLFramebuffer::pushFramebuffer(sourceFbo);
    const bool ok = m_currentCapture->fbo->blitFromRenderTarget(renderTarget, viewport, source, destination);
    GLFramebuffer::popFramebuffer();

    if (!ok) {
        // Not fatal and not silent: the shader falls back to the alpha-only band.
        static int warnings = 0;
        if (warnings < 4) {
            ++warnings;
            qWarning() << "[macos-glass] the background blit was refused for"
                       << w->caption().left(20)
                       << "-- blits unsupported on this GL context?";
        }
    }

    // DIAGNOSE the verifier's question, because the answer costs a relogin.
    //
    // Every other instrument here needs a screen, and this one line decides which
    // of two very different problems you are looking at after logging back in:
    //   ok climbing          -> the desktop IS being captured, so a wrong-looking
    //                           band is a COMPOSITE problem (uv, alpha, colour)
    //   refused climbing     -> there is no capture at all and the band is the old
    //                           opaque alpha path; the GL context cannot blit
    // Without it, "the band looks wrong" and "there was never a band" read the same
    // in the journal, and finding out costs another session.
    static int capturesOk = 0;
    static int capturesRefused = 0;
    if (ok) {
        ++capturesOk;
    } else {
        ++capturesRefused;
    }
    const int attempts = capturesOk + capturesRefused;
    if (attempts == 60 || (attempts % 300) == 0) {
        qInfo() << "[macos-glass] capture: ok=" << capturesOk
                << "refused=" << capturesRefused;
    }
    return ok;
}

void MacosGlassEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                                  EffectWindow *w, int mask, const Region &deviceRegion,
                                  WindowPaintData &data)
{
    // THE CAPTURE HAPPENS HERE, AND BEFORE THE BASE CLASS RUNS.
    //
    // apply() is where the shader's uniforms live, but it never receives the render
    // target, so it cannot capture anything. At this point the screen still holds
    // the DESKTOP: OffscreenEffect::drawWindow is what paints the window over it.
    //
    // The base class is called on the ONLY path out of this function. That is not
    // decoration: verify-chain.sh checks it, and an early return here is the exact
    // shape of the two black screens this project already paid for (HANDOFF §3).
    // DOES THE FRAME REACH THE SCREEN'S EDGE? If it does, an arc there would carve a piece
    // out of the screen itself and show the desktop through it. A maximized window with a
    // visible panel does NOT reach the top edge and keeps its corners; one with the panel
    // hidden does, and does not. A review caught the first version of this gate, which
    // only excluded fullscreen windows and therefore rounded maximized ones.
    //
    // Set here because this is where the viewport is available, and apply() runs after
    // drawWindow for the SAME window, which is what makes a per-paint member safe.
    const Rect screenRect = viewport.renderRect().toRect();
    const Rect frameRect = w->frameGeometry().toRect();
    m_touchesEdge = frameRect.left() <= screenRect.left() || frameRect.top() <= screenRect.top()
        || frameRect.right() >= screenRect.right() || frameRect.bottom() >= screenRect.bottom();

    m_hasBackground = captureBackground(renderTarget, viewport, w);
    OffscreenEffect::drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

void MacosGlassEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data)
{
    // DIAGNOSE: is this called at all? If it is not, setTranslucent() never runs
    // and the shader's alpha is ignored -- which is exactly what the measurement
    // shows (opaque over a dark and a light background, difference 3.2).
    //
    static int pre = 0;
    // ONE GATE, ONE COUNTER, for both halves of the message. The previous version
    // incremented `pre` only while it was below six and then asked `pre <= 6`
    // afterwards: once the counter stopped at six, that condition was TRUE ON EVERY
    // PAINT of every window, and the journal filled with thousands of identical lines a
    // second (seen in the real journal, 2026-10-14). A counter that stops incrementing
    // cannot be used as a gate, and a diagnostic that floods the log destroys the thing
    // it exists for: the journal stopped being readable exactly when it was needed.
    const bool shouldLog = m_active && w->isNormalWindow() && pre < 6;
    if (shouldLog) {
        ++pre;
        qInfo() << "[macos-glass] prePaintWindow" << w->caption().left(20)
                << "normal=" << w->isNormalWindow() << "active=" << m_active;
    }
    if (m_active && w->isNormalWindow()) {
        // The scene blends a window only if it is told the window is translucent.
        // The shader writing an alpha is not enough on its own.
        data.setTranslucent();
        if (shouldLog) {
            qInfo() << "[macos-glass] setTranslucent called for" << w->caption().left(20);
        }
    }
    // Continue the chain: prePaintWindow must re-enter it like the others.
    OffscreenEffect::prePaintWindow(view, w, data);
}

void MacosGlassEffect::apply(EffectWindow *w, int mask, WindowPaintData &data, WindowQuadList &quads)
{
    Q_UNUSED(w)
    Q_UNUSED(mask)
    Q_UNUSED(quads)
    // The material is a shader over the redirected texture, so the geometry itself
    // is untouched. M1.3 (refraction) will deform quads here.
    Q_UNUSED(data)

    // RE-ASSERT THE SHADER ON EVERY PAINT.
    //
    // setShader() was called once, when the window was added. The effect then
    // vanished as soon as the window was moved or focus changed: KWin repaints a
    // window on those events, and the paint path does not necessarily keep the
    // shader that was registered at add time. apply() is called by
    // OffscreenEffect::drawWindow on EVERY paint, just before the texture is
    // drawn, so this is the place that keeps it applied.
    //
    // Diagnose counter: if the band disappears while this keeps counting, the
    // shader is being overwritten elsewhere and that is the place to look.
    // Count apply() calls PER WINDOW, and log a periodic summary. The symptom to
    // chase is a window that HAD the material and lost it when another window was
    // created. A single global counter cannot show that: what matters is whether
    // apply() keeps being called for a window that is still on screen.
    static QHash<QString, int> counts;
    static int total = 0;
    const QString key = w->caption();
    ++counts[key];
    ++total;
    if (total == 200 || (total % 300) == 0) {
        QString resumen;
        for (auto it = counts.constBegin(); it != counts.constEnd(); ++it) {
            resumen += QStringLiteral("[%1 x%2] ").arg(it.key().left(14)).arg(it.value());
        }
        qInfo() << "[macos-glass] apply() totals:" << resumen;
    }
    if (!m_shader) {
        return;
    }
    setShader(w, m_shader.get());

    // Uniforms belong here, not in slotWindowAdded: one shader object is shared by
    // all windows, so anything written once at add time is a global that the next
    // window overwrites. Setting them per paint makes each window's band its own.
    const QSize size = w->frameGeometry().size().toSize();
    if (size.width() <= 0 || size.height() <= 0) {
        return;
    }
    qreal barHeight = 0.0;
    if (w->hasDecoration()) {
        barHeight = w->clientGeometry().top() - w->frameGeometry().top();
    }
    if (barHeight < 0.0) {
        barHeight = 0.0;
    }

    ShaderManager::instance()->pushShader(m_shader.get());
    m_shader->setUniform("uRadius", float(m_frostRadius));
    m_shader->setUniform("uTexelSize",
                         QVector2D(1.0f / size.width(), 1.0f / size.height()));
    m_shader->setUniform("uTextureSize",
                         QVector2D(float(size.width()), float(size.height())));
    m_shader->setUniform("uTitleBarHeight", float(barHeight));
    m_shader->setUniform("uGlassAlpha", m_glassAlpha);
    m_shader->setUniform("uChromeLow", m_chromeLow);
    // WHICH WINDOWS GET ROUNDED CORNERS, and it is not all of them. A fullscreen window
    // IS the screen: rounding its corners would carve arcs out of the screen itself and
    // show the desktop behind them. A window with client-side decoration is the one case
    // this effect deliberately leaves alone everywhere else (a guessed band there was
    // tried and removed), so its corners are left alone too. That leaves exactly the
    // windows the material covers: normal, decorated, not fullscreen.
    const bool shouldRound = m_cornerRadius > 0
        && w->isNormalWindow() && w->hasDecoration() && !w->isFullScreen() && !m_touchesEdge;
    m_shader->setUniform("uCornerRadius", shouldRound ? float(m_cornerRadius) : 0.0f);
    m_shader->setUniform("uVibrancy", m_vibrancy);
    m_shader->setUniform("uRim", m_rim);
    m_shader->setUniform("uMaterialBoost", m_materialBoost);
    m_shader->setUniform("uBackgroundFlipV", m_backgroundFlipV ? 1.0f : 0.0f);
    m_shader->setUniform("uBackgroundRadius", float(m_backgroundRadius));

    // The captured desktop goes on texture unit 1: unit 0 is the window's own
    // texture, bound by KWin. The texture is NOT unbound afterwards on purpose --
    // apply() runs BEFORE the draw, so unbinding here would leave the draw without
    // its background. Leaving it bound on a unit KWin does not use for the window is
    // the smaller risk, and unit 0 is made active again for whoever draws next.
    const bool hasCapture = m_hasBackground && m_currentCapture && m_currentCapture->texture;
    if (hasCapture) {
        glActiveTexture(GL_TEXTURE0 + 1);
        m_currentCapture->texture->bind();
        m_shader->setUniform("background", 1);
        glActiveTexture(GL_TEXTURE0);
        // The kernel's spacing is expressed in SCREEN pixels, so this is the texel of
        // the full-size region -- not of the reduced texture, which is factor times
        // bigger per texel and would multiply every radius by that factor.
        // OFF BY DEFAULT: with the switch off this sends the identity, which is exactly the
        // sampling that was verified before this existed.
        const QVector2D uvOffset = m_captureSubRect ? m_sampleOffset : QVector2D(0.0f, 0.0f);
        const QVector2D uvScale = m_captureSubRect ? m_sampleScale : QVector2D(1.0f, 1.0f);
        m_shader->setUniform("uBackgroundOffset", uvOffset);
        m_shader->setUniform("uBackgroundScale", uvScale);
        if (m_captureRegion.width() > 0 && m_captureRegion.height() > 0) {
            m_shader->setUniform("uBackgroundTexel",
                                 QVector2D(1.0f / m_captureRegion.width(),
                                           1.0f / m_captureRegion.height()));
        }
    }
    m_shader->setUniform("uHasBackground", hasCapture ? 1.0f : 0.0f);
    ShaderManager::instance()->popShader();
}

} // namespace KWin

#include "glass.moc"
