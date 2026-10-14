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

    // Client-side-decorated windows (Zen Browser and most Electron apps) draw
    // their own title bar INSIDE the client area, so frameGeometry() and
    // clientGeometry() are identical and the band height cannot be measured.
    // KWin does not expose that region, so no effect can locate it without
    // guessing -- and guessing geometry is what cost four session restarts in M1.1.
    //
    // So the guess is explicit, configurable and off by default: a guessed band on
    // a window that has nothing there would blur content for no reason. Raise it
    // for CSD apps, e.g. 70 for Zen Browser, and it applies to every window that
    // reports no measurable title bar.
    // Configurable from kwinrc, so changing it does not need a rebuild:
    //   kwriteconfig6 --file kwinrc --group Effect-macosglass2 --key CsdBarHeight 70
    //   qdbus6 org.kde.KWin /KWin reconfigure
    int m_csdBarHeight = 0;
    int m_frostRadius = kFrostRadius;

    // Opacity of the frost layer, from the kit. Not used by the blur itself yet:
    // it belongs with the veil work in M1.5.
    static constexpr float kFrostOpacity = 0.25f;   // kit: opacity 25

    // Whether the material is applied at all. Turning it off leaves the windows
    // untouched, which is what makes the measurement possible.
    bool m_active = true;
};

} // namespace KWin
