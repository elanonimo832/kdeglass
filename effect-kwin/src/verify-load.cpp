// Uses EXACTLY the path used by KWin::PluginEffectLoader (verified in the
// source code): m_pluginSubDirectory = "kwin/effects/plugins".
#include <QCoreApplication>
#include <QPluginLoader>
#include <KPluginFactory>
#include <KPluginMetaData>
#include <effect/effect.h>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    for (const char *sub : {"kwin/effects/", "kwin/effects/plugins"}) {
        const auto lista = KPluginMetaData::findPlugins(QString::fromLatin1(sub));
        std::printf("\nfindPlugins(\"%s\") -> %lld\n", sub, static_cast<long long>(lista.size()));
        for (const auto &md : lista) {
            if (!md.pluginId().contains(QStringLiteral("macos")))
                continue;
            QPluginLoader loader(md.fileName());
            QObject *obj = loader.instance();
            auto *f = obj ? qobject_cast<KWin::EffectPluginFactory *>(obj) : nullptr;
            std::printf("   pluginId      : %s\n", md.pluginId().toLocal8Bit().constData());
            std::printf("   file          : %s\n", md.fileName().toLocal8Bit().constData());
            std::printf("   factory       : %s\n", f ? "YES" : "NO");
            if (f)
                std::printf("   isSupported() : %s  <-- what KWin checks\n",
                            f->isSupported() ? "YES" : "NO");
        }
    }
    return 0;
}
