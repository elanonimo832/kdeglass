#pragma once

#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <effect/offscreeneffect.h>

#include <opengl/glframebuffer.h>
#include <opengl/gltexture.h>

#include <memory>

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
     * Copies the desktop behind @a w into m_background. Returns false when there is
     * nothing to copy (no GL framebuffer to read, the window is off screen, blits
     * unsupported); the shader then keeps the old alpha-only behaviour instead of
     * showing a texture that was never filled.
     */
    bool captureBackground(const RenderTarget &renderTarget, const RenderViewport &viewport,
                           EffectWindow *w);

    bool loadShader();

    std::unique_ptr<GLShader> m_shader;

    // ---------------------------------------------------------------------
    // M1.3a -- the captured desktop.
    //
    // The texture is the window's FRAME at device resolution, not just the band.
    // That is deliberate: a frame-sized capture lines up with the window's own
    // offscreen texture UV for UV, so the composite cannot drift. Band-only is an
    // optimisation for when this is known to work.
    //
    // ONE texture, shared by every window -- which is the hazard that cost M1.2b
    // (one shader object, many windows, the last one won). It is safe here ONLY
    // because capture and draw happen inside the SAME drawWindow() call:
    //     capture(A) -> draw(A) -> capture(B) -> draw(B)
    // If a band ever shows ANOTHER window's background, this assumption has broken
    // and the capture has to become per window.
    // ---------------------------------------------------------------------
    std::unique_ptr<GLTexture> m_background;
    std::unique_ptr<GLFramebuffer> m_backgroundFbo;
    QSize m_backgroundSize;
    bool m_hasBackground = false;

    // THE ONE THING THAT CANNOT BE SETTLED WITHOUT A SCREEN.
    //
    // Two GL textures are involved: the window's (created by OffscreenEffect) and
    // the capture's (created here). The window's is known to have its v axis
    // inverted relative to window coordinates -- measured in M1.2b, and that is why
    // the band test uses (1 - vTexCoord.y), i.e. v = 0 is the BOTTOM of the window.
    //
    // The default (false) rests on one argument, not on a coin toss: the capture is
    // filled by a framebuffer blit whose destination is in texture-local
    // coordinates, and for an FBO's texture v = 0 is the bottom row of the
    // framebuffer. So the capture's v axis is ALSO bottom-up, and the two textures
    // agree -> no flip. What would falsify it is KWin mapping `destination` through
    // a top-left convention internally, which is not visible from the headers.
    //
    // Because that is an argument and not a measurement, it is a setting rather
    // than a literal in the shader:
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key BackgroundFlipV true
    //   qdbus6 org.kde.KWin /KWin reconfigure
    // If the band shows the desktop UPSIDE DOWN, that is the switch.
    bool m_backgroundFlipV = false;

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
    // user put it exactly: "el fondo blanco no me deja ver nada, solo lo se por
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
    // Too low and the title text becomes unreadable; too high and it is paint.
    // ---------------------------------------------------------------------
    static constexpr float kGlassAlpha = 0.55f;   // how much of the bar stays opaque

    // Opacity of the frost layer, from the kit. Not used by the blur itself yet:
    // it belongs with the veil work in M1.5.
    static constexpr float kFrostOpacity = 0.25f;   // kit: opacity 25

    // Whether the material is applied at all. Turning it off leaves the windows
    // untouched, which is what makes the measurement possible.
    bool m_active = true;
};

} // namespace KWin
