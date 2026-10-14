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
        // -----------------------------------------------------------------
        // M1.1 -- a flat colour patch at the window's TOP-LEFT corner.
        //
        // COORDINATES, which is what the first version got wrong. The window
        // moved up and the patch moved down, because frameGeometry() is the
        // window's position in GLOBAL screen space being used as if it were an
        // offset inside the window.
        //
        // paintWindow() gets the SCREEN's render target, and the window is drawn
        // by projecting its geometry into it. The pattern KWin's own blur effect
        // uses (src/plugins/blur/blur.cpp) is:
        //   1. logical global rect   = frameGeometry() + data translation
        //   2. viewport.mapToDeviceCoordinates() to reach device pixels
        //   3. viewport.deviceSize() is the framebuffer size, whose origin is
        //      the TOP-LEFT, while glScissor's origin is BOTTOM-LEFT.
        //
        // data.xTranslation()/yTranslation() matter: they carry the window's
        // displacement during animations, so ignoring them makes the patch lag.
        // -----------------------------------------------------------------
        // -----------------------------------------------------------------
        // CALIBRATION: compute the patch origin BOTH ways and log both, so the
        // right one can be picked from real numbers instead of from deduction.
        //
        // The two candidates differ by a translation that RenderViewport applies:
        //   mapToDeviceCoordinates() does
        //       rect.translate(-renderRect.topLeft()).scale(s).translate(renderOffset)
        // so it first subtracts the screen's corner. If the rect you pass is
        // ALREADY screen-local, that subtraction shifts the patch by the screen's
        // own origin -- which is exactly the inversion being observed.
        //
        //   A) mapped   = viewport.mapToDeviceCoordinates(globalRect)
        //   B) direct   = globalRect scaled by viewport.scale()
        //
        // Whichever tracks the window on screen is the correct one.
        // -----------------------------------------------------------------
        const RectF globalRect = w->frameGeometry().translated(
            QPointF(data.xTranslation(), data.yTranslation()));
        const RectF mappedRect = viewport.mapToDeviceCoordinates(globalRect);
        const RectF directRect{
            globalRect.x() * viewport.scale(),
            globalRect.y() * viewport.scale(),
            globalRect.width() * viewport.scale(),
            globalRect.height() * viewport.scale(),
        };

        // Use the DIRECT one for now; the log will say which is right.
        const RectF deviceRect = directRect;
        const int x = qRound(deviceRect.x());
        const int y = qRound(deviceRect.y());
        const int size = qRound(static_cast<double>(kMarkerSize) * viewport.scale());
        const int fbHeight = renderTarget.size().height();

        if (size > 0 && fbHeight > 0) {
            // Restore KWin's own scissor state instead of blindly disabling it:
            // KWin clips window painting with the scissor test, and clobbering it
            // can leave artefacts on unrelated parts of the frame.
            GLint previousBox[4] = {0, 0, 0, 0};
            const GLboolean scissorWasEnabled = glIsEnabled(GL_SCISSOR_TEST);
            glGetIntegerv(GL_SCISSOR_BOX, previousBox);

            glEnable(GL_SCISSOR_TEST);
            // Direct device coordinates. The earlier version flipped Y
            // (fbHeight - y - size) on the assumption that glScissor's origin is
            // bottom-left. That flip is what made the patch move OPPOSITE to its
            // window: frameGeometry().y() is already measured from the top of the
            // screen, and the flip turned "down the screen" into "up the screen".
            glScissor(x, y, size, size);
            glClearColor(kMarkerR, kMarkerG, kMarkerB, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);

            glScissor(previousBox[0], previousBox[1], previousBox[2], previousBox[3]);
            if (!scissorWasEnabled) {
                glDisable(GL_SCISSOR_TEST);
            }
        }

        // Position logging for calibrating the coordinate space. Every draw is
        // logged (capped) so a window move can be correlated with the patch.
        static int logged = 0;
        if (logged < 40) {
            ++logged;
            qInfo() << "[macos-glass] CALIB"
                    << "cap=" << w->caption().left(12)
                    << "frameGeom=" << w->frameGeometry()
                    << "renderRectTL=" << viewport.renderRect().topLeft()
                    << "MAP=" << mappedRect
                    << "DIRECT=" << directRect
                    << "scale=" << viewport.scale()
                    << "fbH=" << fbHeight;
        }
    }

    effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

} // namespace KWin

// ESSENTIAL: the macro defines a class with Q_OBJECT in this .cpp; without this
// include its moc is not generated and the plugin does not export qt_plugin_instance.
#include "glass.moc"
