#pragma once

#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <effect/offscreeneffect.h>

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

    // Marks the window translucent, which is what makes the scene BLEND the alpha
    // the shader writes. Without this the alpha is ignored and the bar stays
    // opaque no matter what the shader outputs -- the same class of mistake as
    // the unbound uniform: correct output, never used.
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data) override;

private:
    void slotWindowAdded(EffectWindow *w);
    void slotWindowDeleted(EffectWindow *w);

    bool loadShader();

    std::unique_ptr<GLShader> m_shader;

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
