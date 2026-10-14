#pragma once

#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>

namespace KWin
{

/**
 * Material estilo macOS: borde oscurecido por dentro del marco de la ventana.
 *
 * El shader del material (difusion, refraccion, dispersion, realce especular) es
 * el paso siguiente. Ahora mismo el efecto solo se engancha a la cadena de pintado
 * y no dibuja nada.
 *
 * HISTORIA IMPORTANTE (INCIDENTE.md): este efecto dejo la pantalla negra dos veces.
 * La causa NO era el codigo, sino el identificador: el mismo codigo compilado como
 * `macosglass` rompia el render, y con un nombre nuevo (`testglass2`) funcionaba.
 * Por eso el plugin se instala ahora como `macosglass2`.
 */
class MacosGlassEffect : public Effect
{
    Q_OBJECT

public:
    MacosGlassEffect();
    ~MacosGlassEffect() override;

    static bool supported();

    void reconfigure(ReconfigureFlags flags) override;

    // CRITICO: si se sobreescribe, TIENE que continuar la cadena llamando a
    // effects->paintWindow(). Ver el comentario en glass.cpp.
    void paintWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                     EffectWindow *w, int mask, const Region &deviceRegion,
                     WindowPaintData &data) override;

private:
    // Del kit: el borde del material no es un gris propio, es el primitivo de velo.
    // `Fills - Opaque / Secondary` = negro al 8 % en claro, blanco al 8 % en oscuro.
    int m_borderAlpha = 20;
    qreal m_borderWidth = 1.0;
};

} // namespace KWin
