#pragma once

#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>

namespace KWin
{

/**
 * macOS-style material: border darkened inside the window frame.
 *
 * The material shader (diffusion, refraction, dispersion, specular highlight) is
 * the next step. Right now the effect only hooks into the paint chain
 * and draws nothing.
 *
 * IMPORTANT HISTORY (INCIDENT.md): this effect left the screen black twice.
 * The cause was NOT the code, but the identifier: the same code compiled as
 * `macosglass` broke rendering, and with a new name (`testglass2`) it worked.
 * That is why the plugin is now installed as `macosglass2`.
 */
class MacosGlassEffect : public Effect
{
    Q_OBJECT

public:
    MacosGlassEffect();
    ~MacosGlassEffect() override;

    static bool supported();

    void reconfigure(ReconfigureFlags flags) override;

    // CRITICAL: if it is overridden, it MUST continue the chain by calling
    // effects->paintWindow(). See the comment in glass.cpp.
    void paintWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                     EffectWindow *w, int mask, const Region &deviceRegion,
                     WindowPaintData &data) override;

private:
    // From the kit: the material border is not a gray of its own, it is the veil primitive.
    // `Fills - Opaque / Secondary` = black at 8% in light, white at 8% in dark.
    int m_borderAlpha = 20;
    qreal m_borderWidth = 1.0;
};

} // namespace KWin
