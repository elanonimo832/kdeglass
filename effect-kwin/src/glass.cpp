#include "glass.h"

#include <KPluginFactory>
#include <QLoggingCategory>

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(MacosGlassEffect, "metadata.json",
                              return true;)

MacosGlassEffect::MacosGlassEffect()
{
    qInfo() << "[macos-glass] cargado. Borde oscurecido activo, alfa" << m_borderAlpha;
    reconfigure(ReconfigureAll);
}

MacosGlassEffect::~MacosGlassEffect() = default;

bool MacosGlassEffect::supported()
{
    // TEST: it is always declared supported. See INCIDENT.md for why
    // (a check like `effects != nullptr` returned false and KWin discarded it).
    return true;
}

void MacosGlassEffect::reconfigure(ReconfigureFlags)
{
    // Values from the kit (tokens.toml). The material shader is the next step.
    m_borderAlpha = 20;   // black at 8%: Fills - Opaque / Secondary
    m_borderWidth = 1.0;
}

void MacosGlassEffect::paintWindow(const RenderTarget &renderTarget,
                                   const RenderViewport &viewport,
                                   EffectWindow *w, int mask,
                                   const Region &deviceRegion, WindowPaintData &data)
{
    // ---------------------------------------------------------------------
    // GOLDEN RULE OF THE PAINT CHAIN (INCIDENT.md, 2026-10-13).
    //
    // EffectsHandler::paintWindow() calls ONE single effect per invocation; the
    // chain advances because Effect::paintWindow() —the base— re-enters
    // effects->paintWindow(). If an effect overrides paintWindow() and does NOT call
    // the base, the chain is cut, finalPaintWindow() is not run and NO
    // window is drawn (the Plasma desktop is just another window).
    //
    // That is why ALL paths end up calling effects->paintWindow().
    // ---------------------------------------------------------------------
    if (w && w->isNormalWindow() && !w->isFullScreen()
        && !(mask & PAINT_WINDOW_TRANSFORMED)) {
        // The border will be drawn with GL here. The material shader is the
        // next step; for now only the hook is left marked.
    }

    effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

} // namespace KWin

// ESSENTIAL: the macro defines a class with Q_OBJECT in this .cpp; without this
// include its moc is not generated and the plugin does not export qt_plugin_instance.
#include "glass.moc"
