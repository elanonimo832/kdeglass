#pragma once

#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <effect/offscreeneffect.h>

#include <opengl/glframebuffer.h>
#include <opengl/gltexture.h>

#include <map>
#include <memory>
#include <utility>

namespace KWin
{

class GLShader;

/**
 * macOS-style material for windows.
 *
 * M1.1 proved pixels can be put on screen. M1.2 is diffusion: the window's own
 * content is blurred, so it visibly softens.
 *
 * WHY OffscreenEffect AND NOT Effect
 *   A plain Effect receives the SCREEN's framebuffer and can only clear regions
 *   of it -- enough for M1.1's flat patch, not enough to blur a window. Blurring
 *   needs the window's own texture, so the effect derives from OffscreenEffect:
 *   KWin renders the window into an offscreen texture, and the effect replaces
 *   the drawing with a shader that samples that texture. This is the same base
 *   class KWin's own blur and invert effects use.
 *
 * IMPORTANT HISTORY (INCIDENT.md): this effect left the screen black twice. The
 * cause was NOT the code but the identifier: the same code compiled as
 * `macosglass` broke rendering, and with a new name it worked. That is why the
 * plugin is installed as `macosglass2`.
 */
class MacosGlassEffect : public OffscreenEffect
{
    Q_OBJECT

public:
    MacosGlassEffect();
    ~MacosGlassEffect() override;

    static bool supported();

    void reconfigure(ReconfigureFlags flags) override;

    /**
     * OffscreenEffect handles the redirection and the shader; this override only
     * decides WHICH windows get the treatment.
     */
    void apply(EffectWindow *w, int mask, WindowPaintData &data, WindowQuadList &quads) override;

    /**
     * M1.3a: capture what is painted UNDER the window, before the window is drawn
     * on top of it. This is the only place the render target is available -- apply()
     * does not receive it -- and the desktop is still on screen at this moment,
     * because OffscreenEffect::drawWindow is what replaces it with the window.
     *
     * The base class is called on the single exit path: verify-chain.sh checks that
     * property, and an early return here is the shape of the two black screens.
     */
    void drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w,
                    int mask, const Region &deviceRegion, WindowPaintData &data) override;

    // Marks the window translucent, which is what makes the scene BLEND the alpha
    // the shader writes. Without this the alpha is ignored and the bar stays
    // opaque no matter what the shader outputs -- the same class of mistake as
    // the unbound uniform: correct output, never used.
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data) override;

private:
    void slotWindowAdded(EffectWindow *w);
    void slotWindowDeleted(EffectWindow *w);

    /**
     * Copies the desktop behind @a w into one of the cached capture textures, reduced by
     * the frost's factor. Returns false when there is nothing to copy (no GL framebuffer to
     * read, the window is off screen, blits unsupported); the shader then keeps the old
     * alpha-only behaviour instead of showing a texture that was never filled.
     */
    bool captureBackground(const RenderTarget &renderTarget, const RenderViewport &viewport,
                           EffectWindow *w);

    bool loadShader();

    std::unique_ptr<GLShader> m_shader;

    // ---------------------------------------------------------------------
    // M1.3a -- the captured desktop.
    //
    // The texture is the window's EXPANDED geometry -- frame plus the decoration's
    // shadow margins -- because that is exactly the region KWin's own offscreen
    // texture covers and the region the shader's vTexCoord runs across. Capturing the
    // frame instead would sample the desktop shifted by the shadow margin. Band-only
    // is an optimisation for when this is known to work.
    //
    // ONE texture, shared by every window -- which is the hazard that cost M1.2b
    // (one shader object, many windows, the last one won). Two facts make it safe
    // here, and both come from KWin 6.7.5's own source rather than from hope:
    //   1. EffectsHandler::drawWindow() advances the effect cursor BEFORE calling an
    //      effect and rewinds it after (effecthandler.cpp): while our drawWindow runs,
    //      the cursor is past us. The nested effects->drawWindow() that
    //      OffscreenEffect::maybeRender() does to re-render the window into its own
    //      FBO therefore resumes AFTER this effect -- it does NOT re-enter us, so the
    //      capture is not overwritten by the window's own texture. If it ever did,
    //      every OffscreenEffect would recurse forever.
    //   2. capture(A) -> draw(A) -> capture(B) -> draw(B) within one compositing pass,
    //      so the texture is consumed before the next window writes it.
    // If a band ever shows ANOTHER window's background, fact 2 has broken and the
    // capture has to become per window.
    // ---------------------------------------------------------------------
    // ONE PAIR PER DISTINCT CAPTURE SIZE, not one pair for the whole effect.
    //
    // With a single pair, a frame in which two windows of DIFFERENT sizes both repaint
    // allocated and freed a texture and a framebuffer twice -- per frame, for as long as
    // that kept happening, which is a terminal with a blinking cursor next to a video.
    // The cache keeps the uv maths identical (it is still a texture per size, not one
    // packed texture with a scale uniform) and the network of assumptions above intact:
    // entries are used inside the same capture/draw call that fills them.
    struct CaptureSlot {
        std::unique_ptr<GLTexture> texture;   // declared first, so the FBO dies first
        std::unique_ptr<GLFramebuffer> fbo;
    };
    std::map<std::pair<int, int>, std::unique_ptr<CaptureSlot>> m_captures;
    // When each entry was last used, so the cap evicts the LEAST RECENTLY USED rather than
    // whatever `std::map` happens to put first -- which is the smallest size, and a small
    // terminal is the window this cache exists for.
    std::map<std::pair<int, int>, quint64> m_lastUse;
    quint64 m_useClock = 0;
    CaptureSlot *m_currentCapture = nullptr;   // the one this paint uses; apply() binds it
    static constexpr int kMaxCaptureSlots = 4;   // enough for a desktop, bounded on purpose

    QSize m_captureRegion;    // the region the CURRENT capture covers, in screen px

    // THE ONE OPEN QUESTION OF M1.3a, as a live switch. The capture covers the window's
    // EXPANDED geometry while every size the shader uses comes from the FRAME; if vTexCoord
    // runs across the frame, the backdrop has to be sampled at the frame's sub-rectangle.
    // Off = identity = the sampling that was verified before this existed.
    //
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key CaptureSubRect true
    //   qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2
    //
    // Then run measure-alignment.py with BackgroundRadius=0: the setting that reports
    // (0, 0) is the true one. Both are stable, so this is a measurement, not a guess.
    // ---------------------------------------------------------------------
    // The material's EDGE and its AMPLIFICATION, both from the user's own measurement of a
    // macOS Dock: bright bands of 215-236 along the top and 206-218 along the bottom (the rim),
    // and a colour that tracks the backdrop with a gain of ~1.6, which no blend can produce.
    //
    //   kwriteconfig6 ... --key Rim 0.3          (0 = no edge highlight; 0.2 is subtle)
    //   kwriteconfig6 ... --key MaterialBoost 1.6 (1.0 = off; 1.6 is what Apple measures)
    // ---------------------------------------------------------------------
    static constexpr float kRim = 0.20f;
    float m_rim = kRim;
    static constexpr float kMaterialBoost = 1.20f;
    float m_materialBoost = kMaterialBoost;

    static constexpr bool kCaptureSubRect = false;
    bool m_captureSubRect = kCaptureSubRect;
    QVector2D m_sampleOffset{0.0f, 0.0f};   // the frame inside the capture, normalized
    QVector2D m_sampleScale{1.0f, 1.0f};
    bool m_hasBackground = false;

    // Whether the window's frame reaches the screen's edge, computed in drawWindow (the
    // only place with a viewport) and read by apply() for the same window. Rounding a
    // window that reaches the edge would carve an arc out of the SCREEN.
    bool m_touchesEdge = false;

    // THE v AXIS QUESTION, whose answer is NO FLIP -- and it is settled, not a coin toss.
    //
    // This block used to be titled "the one thing that cannot be settled without a screen",
    // which stopped being true when KWin's own blit code was read: the capture is filled by
    // a framebuffer blit whose destination is in texture-local coordinates, and both
    // textures involved are bottom-up (the window texture was measured in M1.2b -- that is
    // why the band test uses (1 - vTexCoord.y) -- and the blit preserves that). The default
    // (false) is therefore correct, and the knob stays for a ROTATED output, where the blit
    // takes a different branch.
    //
    // Because that is an argument and not a measurement, it is a setting rather
    // than a literal in the shader:
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key BackgroundFlipV true
    //   qdbus6 org.kde.KWin /KWin reconfigure
    // If the band shows the desktop UPSIDE DOWN, that is the switch.
    bool m_backgroundFlipV = false;

    // ---------------------------------------------------------------------
    // M1.3a step 3a -- the frost over the captured desktop.
    //
    // Step 2 composites the desktop SHARP. macOS shows it frosted, and the kit's
    // `frost 6/16/16` is what this uses: `BackgroundRadius` is the OUTER radius in
    // texels of the capture, the inner one is 6/16 of it, and the shader samples both
    // scales (glass.cpp explains why a single 3x3 was not enough).
    //
    // 16 IS THE DEFAULT because 16 is what the kit says and what the user's eye picked
    // on screen: at 0 the band is the sharp composite step 2 was verified with, and at
    // 6 the frost is real but invisible against anything coarser than text. Worth
    // keeping: a flat wallpaper of 380 px squares cannot show a 6 px blur at all, so
    // "I see no frost" was a fact about the test pattern before the effect.
    //
    // It is still a setting, and the working way to change it is:
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key BackgroundRadius 16
    //   qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2
    // (`/KWin reconfigure` does NOT reach the effects; see the note in reconfigure().)
    //
    // Why the blur does not disturb the step-2 measurement: measure-glass.py compares
    // the band's MEAN colour over two backgrounds, and a blur preserves the mean. So
    // the GLASS/OPAQUE verdict is unaffected by this knob.
    // ---------------------------------------------------------------------
    static constexpr int kBackgroundRadius = 16;   // kit: frost outer 16; 0 = sharp

    int m_backgroundRadius = kBackgroundRadius;

    // The factor the backdrop is CAPTURED at, which is what turns the frost from a
    // sample into an average (see captureBackground). 0 derives it from the radius.
    int m_backgroundDownsample = 0;

    // ---------------------------------------------------------------------
    // Vibrancy: the minimum CONTRAST the chrome should keep against the glass.
    //
    // 0 DISABLES IT, and 0 is the default on purpose: it changes the colour of the title,
    // which is a decision for a screen and not for a commit. The problem it answers is
    // real and reported -- the theme's title is dark, the frosted backdrop can be dark,
    // and with little of the bar's own colour kept the title disappears. macOS adapts the
    // chrome to the material; the shader does the same, and only for achromatic chrome,
    // so the traffic lights keep their colours.
    //
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key Vibrancy 0.35
    //   qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2
    // ---------------------------------------------------------------------
    // ON by default, because Apple's material and Apple's content go together: at a quarter
    // opacity the title of this theme (a dark #404040) has too little contrast against a dark
    // backdrop, and macOS answers that by flipping the content rather than by making the
    // material more opaque. 0 turns it off.
    static constexpr float kVibrancy = 0.35f;
    float m_vibrancy = kVibrancy;

    // ---------------------------------------------------------------------
    // M1.2 -- diffusion.
    //
    // Values from the kit's Liquid Glass parameters (tokens.toml):
    //   frost    6 / 16 / 16
    //   refraction 70, dispersion 20, depth 30   <- M1.3 and later
    //
    // `frost` is a three-part figure; 6 is the innermost radius. M1.2 uses it as
    // the blur radius, because a single radius is what a box blur takes. The two
    // 16s describe the outer falloff and belong with the edge work in M1.3/M1.5.
    // ---------------------------------------------------------------------
    static constexpr int kFrostRadius = 6;    // kit: frost 6/16/16

    int m_frostRadius = kFrostRadius;

    // ---------------------------------------------------------------------
    // M1.3a -- real glass.
    //
    // M1.2b blurred the WINDOW'S OWN texture and was invisible in practice. The
    // user put it exactly: "el backdrop blanco no me deja ver nada, solo lo se por
    // los botones y el titulo". Blurring a uniform colour returns that same
    // uniform colour, so there was nothing to see beyond unreadable text.
    //
    // macOS does not blur the bar; it makes the bar translucent and shows the
    // desktop behind it. That is the difference between "smudged" and "glass", and
    // it is also what makes every LATER step visible: refraction, dispersion and
    // the specular highlight all deform or light up what shows through. Without a
    // background to show, all of them would be equally invisible.
    //
    // The band keeps some of the window's own colour and lets the rest through.
    // Too low and the bar's flat colour stops reading as a bar; too high and it is
    // paint. It no longer decides whether the TITLE is readable: the chrome is drawn
    // crisp on top of the glass whatever this is (see the fragment shader), so this
    // can now be lowered for more glass without losing the title.
    //
    // It is a setting, because that balance is a taste call and the right way to settle
    // it is on a screen:
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key GlassAlpha 0.4
    //   qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect macosglass2
    // ---------------------------------------------------------------------
    // APPLE'S OWN NUMBER, not a taste of mine: tokens/tokens-kit.toml, [liquid_glass],
    // `opacity = 25`. The material is a quarter opaque. The user's "el efecto es muy blanco"
    // was this constant at 0.55 keeping too much of the theme's near-white bar.
    static constexpr float kGlassAlpha = 0.25f;   // default: how much of the bar stays

    float m_glassAlpha = kGlassAlpha;

    // How much deviation from the bar's own (median) tone counts as chrome, in luminance.
    // The upper threshold is three times this. Lower = more of the bar is drawn crisp. There
    // is no width knob any more: the baseline is the median tone, which has no halo to tune.
    static constexpr float kChromeLow = 0.06f;
    float m_chromeLow = kChromeLow;

    // ---------------------------------------------------------------------
    // M2 (as much as M1.3a needed): the window's rounded corners.
    //
    // This theme's SVG HAS a 12 px arc for its top corners, but aurorae draws the
    // corner piece inside a cell as narrow as the frame border, and this theme sets
    // that to 1 px -- so the arc is clipped away and the frame is a rectangle. The
    // effect therefore draws the shape itself: a rounded rectangle of this radius,
    // outside which the fragment is discarded, which lets the desktop through and
    // makes the corner round. The shadow lives outside the frame and is untouched.
    //
    // 0 disables it and leaves whatever the decoration drew.
    static constexpr int kCornerRadius = 16;   // 12 read small on a 4K 27" panel
    int m_cornerRadius = kCornerRadius;


    // Opacity of the frost layer, from the kit. Not used by the blur itself yet:
    // it belongs with the veil work in M1.5.
    static constexpr float kFrostOpacity = 0.25f;   // kit: opacity 25

    // Whether the material is applied at all. Turning it off leaves the windows
    // untouched, which is what makes the measurement possible.
    bool m_active = true;
};

} // namespace KWin
