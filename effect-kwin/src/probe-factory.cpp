// Prueba la fabrica del .so RECIEN COMPILADO (por ruta, no por la ruta del sistema).
#include <QCoreApplication>
#include <QPluginLoader>
#include <KPluginFactory>
#include <effect/effect.h>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc < 2) { std::printf("uso: probar-fabrica <ruta.so>\n"); return 1; }
    QPluginLoader loader(QString::fromLocal8Bit(argv[1]));
    QObject *obj = loader.instance();
    std::printf("instancia         : %s\n", obj ? "SI" : "NO");
    if (!obj) { std::printf("error             : %s\n", loader.errorString().toLocal8Bit().constData()); return 1; }
    auto *f = qobject_cast<KWin::EffectPluginFactory *>(obj);
    std::printf("es fabrica        : %s\n", f ? "SI" : "NO");
    if (f) {
        std::printf("isSupported()     : %s   <-- lo que KWin comprueba\n", f->isSupported() ? "SI" : "NO");
        std::printf("enabledByDefault(): %s\n", f->enabledByDefault() ? "SI" : "NO");
    }
    return 0;
}
