// Reproduces EXACTLY the two KWin effect search paths:
//   1. findPlugins("kwin/effects/")  -> C++ plugins in the Qt paths
//   2. findPlugins("kwin/effects/", ...) in the DATA directories -> scripts
#include <QCoreApplication>
#include <QPluginLoader>
#include <KPluginMetaData>
#include <KPluginFactory>
#include <cstdio>

static void listar(const char *etiqueta, const QList<KPluginMetaData> &lista)
{
    std::printf("\n%s -> %lld found\n", etiqueta, static_cast<long long>(lista.size()));
    for (const auto &md : lista) {
        const bool mio = md.pluginId().contains(QStringLiteral("macos"));
        if (!mio && lista.size() > 5)
            continue;
        std::printf("  %s | id=%s\n", mio ? ">>>" : "   ",
                    md.pluginId().toLocal8Bit().constData());
        std::printf("      file : %s\n", md.fileName().toLocal8Bit().constData());
        if (mio) {
            QPluginLoader l(md.fileName());
            std::printf("      load : %s\n", l.load() ? "YES" : "NO");
            if (!l.isLoaded()) std::printf("      err  : %s\n", l.errorString().toLocal8Bit().constData());
        }
    }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    std::printf("libraryPaths:\n");
    for (const QString &p : QCoreApplication::libraryPaths())
        std::printf("  %s\n", p.toLocal8Bit().constData());

    listar("findPlugins(\"kwin/effects/\")",
           KPluginMetaData::findPlugins(QStringLiteral("kwin/effects/")));

    // Without filter and without cache: this way EVERYTHING KWin can discover is shown.
    listar("findPlugins(\"kwin/effects/\") without cache",
           KPluginMetaData::findPlugins(QStringLiteral("kwin/effects/"),
                                        [](const KPluginMetaData &) { return true; }));
    return 0;
}
