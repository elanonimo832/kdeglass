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

    // ---------------------------------------------------------------------
    // M1.1 -- the marker.
    //
    // The effect used to load, join the paint chain and draw NOTHING. The harness
    // could only assert "black = 0 %", which proves it does not BREAK rendering
    // but says nothing about whether it draws.
    //
    // M1.1 paints a flat colour patch in the top-left corner of every normal
    // window. It is deliberately obvious: the point is to prove the whole path
    // works -- bind the framebuffer, set a scissor region, get a colour on
    // screen -- before adding any material on top. It goes away once the
    // material shader exists.
    //
    // A provisional magenta, picked because nothing else in output/ produces it,
    // so a screenshot test can look for it unambiguously.
    // ---------------------------------------------------------------------
    // Saturated cyan, 0x00E5FF. The first choice was a desaturated magenta
    // (0xB33A5B) and it was a bad test instrument: the wallpaper contains 1388
    // pixels within a tolerance of 24 per channel of it, so a screenshot test
    // could not tell the marker from the background. Cyan is not a colour any
    // normal desktop produces, so the delta is unambiguous.
    static constexpr float kMarkerR = 0.00f;   // 0x00
    static constexpr float kMarkerG = 0.90f;   // 0xE5
    static constexpr float kMarkerB = 1.00f;   // 0xFF
    static constexpr int kMarkerSize = 48;     // device pixels, square
};

} // namespace KWin
