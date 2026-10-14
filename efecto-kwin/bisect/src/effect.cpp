// EFECTO MINIMO para biseccion: sin paintWindow, sin constructor con log, sin nada.
#include <effect/effect.h>
#include <effect/effecthandler.h>
#include <KPluginFactory>

namespace KWin {
class BisectEffect : public Effect {
    Q_OBJECT
public:
    BisectEffect() { qInfo() << "[bisect] cargado (minimo, sin paintWindow)"; }
};
}
KWIN_EFFECT_FACTORY_SUPPORTED(KWin::BisectEffect, "metadata.json", return true;)
#include "effect.moc"
