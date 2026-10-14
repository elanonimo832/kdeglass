#include "glass.h"

#include <KPluginFactory>
#include <QLoggingCategory>

// KWin's GL entry points. This header pulls in libepoxy, where glScissor,
// glClear and glClearColor resolve (the effect's .so already links libepoxy
// through libkwin; verified with readelf).
#include <opengl/glutils.h>

// RenderTarget and RenderViewport are only forward-declared by effect.h; the
// drawing code calls size() and scale(), so it needs the full definitions.
#include <core/rendertarget.h>
#include <core/renderviewport.h>

namespace KWin
{

KWIN_EFFECT_FACTORY_SUPPORTED(MacosGlassEffect, "metadata.json",
                              return true;)

MacosGlassEffect::MacosGlassEffect()
{
    qInfo() << "[macos-glass] loaded. Darkened border active, alpha" << m_borderAlpha;
    reconfigure(ReconfigureAll);

    // Force every window to repaint NOW. Without this, an already-visible window
    // is never repainted just because an effect was loaded, so paintWindow() is
    // not called for it and the marker does not appear until something else
    // happens to trigger a repaint. That is exactly what confused the first
    // M1.1 measurement: the marker existed but only on windows that repainted
    // during the effect's 5-second window.
    effects->addRepaintFull();
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
    // DIAGNOSTIC: log on entry, unconditionally, and say which guard fails.
    static int diag = 0;
    if (diag < 6) {
        ++diag;
        qInfo() << "[macos-glass] paintWindow ENTER:"
                << "w=" << (w ? "yes" : "null")
                << "normal=" << (w && w->isNormalWindow())
                << "fullscreen=" << (w && w->isFullScreen())
                << "transformed=" << bool(mask & PAINT_WINDOW_TRANSFORMED)
                << "fbo=" << (renderTarget.framebuffer() ? "yes" : "NULL")
                << "fbosize=" << renderTarget.size()
                << "scale=" << viewport.scale()
                << "caption=" << (w ? w->caption() : QString());
    }

    if (w && w->isNormalWindow() && !w->isFullScreen()
        && !(mask & PAINT_WINDOW_TRANSFORMED) && renderTarget.framebuffer()) {
        // ---------------------------------------------------------------
        // M1.1 -- draw a flat colour patch, with no shader yet.
        //
        // The framebuffer already holds this window's content; we only clear a
        // small region of it. The scissor box limits the clear to that region,
        // which is the cheapest possible proof that the GL path works.
        //
        // Coordinates: frameGeometry() is in logical pixels and the framebuffer
        // is in device pixels, so everything is multiplied by the viewport
        // scale. GL's origin is bottom-left, hence the flip on Y.
        // ---------------------------------------------------------------
        const double scale = viewport.scale();
        const RectF frame = w->frameGeometry();
        const int x = qRound(frame.x() * scale);
        const int y = qRound(frame.y() * scale);
        const int size = qRound(static_cast<double>(kMarkerSize) * scale);
        const int fbHeight = renderTarget.size().height();  // QSize::height() is already int

        if (size > 0 && fbHeight > 0) {
            glEnable(GL_SCISSOR_TEST);
            // bottom-left origin: this puts the marker at the TOP-left corner
            glScissor(x, fbHeight - y - size, size, size);
            glClearColor(kMarkerR, kMarkerG, kMarkerB, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            glDisable(GL_SCISSOR_TEST);
        }

        static bool warned = false;
        if (!warned) {
            qInfo() << "[macos-glass] M1.1 marker drawn for" << w->caption()
                    << "at" << x << y << "size" << size;
            warned = true;
        }
    }

    effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

} // namespace KWin

// ESSENTIAL: the macro defines a class with Q_OBJECT in this .cpp; without this
// include its moc is not generated and the plugin does not export qt_plugin_instance.
#include "glass.moc"
