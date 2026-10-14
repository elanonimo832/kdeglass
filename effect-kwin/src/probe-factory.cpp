// Tests the factory of the JUST COMPILED .so (by path, not by the system path).
#include <QCoreApplication>
#include <QPluginLoader>
#include <KPluginFactory>
#include <effect/effect.h>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc < 2) { std::printf("usage: probar-fabrica <path.so>\n"); return 1; }
    QPluginLoader loader(QString::fromLocal8Bit(argv[1]));
    QObject *obj = loader.instance();
    std::printf("instance          : %s\n", obj ? "YES" : "NO");
    if (!obj) { std::printf("error             : %s\n", loader.errorString().toLocal8Bit().constData()); return 1; }
    auto *f = qobject_cast<KWin::EffectPluginFactory *>(obj);
    std::printf("is factory        : %s\n", f ? "YES" : "NO");
    if (f) {
        std::printf("isSupported()     : %s   <-- what KWin checks\n", f->isSupported() ? "YES" : "NO");
        std::printf("enabledByDefault(): %s\n", f->enabledByDefault() ? "YES" : "NO");
    }
    return 0;
}
