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
    // PRUEBA: se declara soportado siempre. Ver INCIDENT.md para el porque
    // (una comprobacion tipo `effects != nullptr` daba false y KWin lo descartaba).
    return true;
}

void MacosGlassEffect::reconfigure(ReconfigureFlags)
{
    // Valores del kit (tokens.toml). El shader del material es el paso siguiente.
    m_borderAlpha = 20;   // negro al 8 %: Fills - Opaque / Secondary
    m_borderWidth = 1.0;
}

void MacosGlassEffect::paintWindow(const RenderTarget &renderTarget,
                                   const RenderViewport &viewport,
                                   EffectWindow *w, int mask,
                                   const Region &deviceRegion, WindowPaintData &data)
{
    // ---------------------------------------------------------------------
    // REGLA DE ORO DE LA CADENA DE PINTADO (INCIDENT.md, 2026-10-13).
    //
    // EffectsHandler::paintWindow() llama a UN solo efecto por invocacion; la
    // cadena avanza porque Effect::paintWindow() —la base— vuelve a entrar en
    // effects->paintWindow(). Si un efecto sobreescribe paintWindow() y NO llama
    // a la base, la cadena se corta, finalPaintWindow() no se ejecuta y no se
    // dibuja NINGUNA ventana (el escritorio de Plasma es una ventana mas).
    //
    // Por eso TODOS los caminos terminan llamando a effects->paintWindow().
    // ---------------------------------------------------------------------
    if (w && w->isNormalWindow() && !w->isFullScreen()
        && !(mask & PAINT_WINDOW_TRANSFORMED)) {
        // Aqui ira el dibujado del borde con GL. El shader del material es el
        // paso siguiente; ahora solo se deja el enganche marcado.
    }

    effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

} // namespace KWin

// IMPRESCINDIBLE: el macro define una clase con Q_OBJECT en este .cpp; sin este
// include no se genera su moc y el plugin no exporta qt_plugin_instance.
#include "glass.moc"
