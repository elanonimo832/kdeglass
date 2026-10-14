#include <QCoreApplication>
#include <QLibraryInfo>
#include <cstdio>
int main(int argc, char **argv){
    QCoreApplication app(argc, argv);
    std::printf("QT_PLUGIN_PATH del entorno: %s\n",
        qgetenv("QT_PLUGIN_PATH").isEmpty() ? "(vacio)" : qgetenv("QT_PLUGIN_PATH").constData());
    std::printf("\nlibraryPaths de Qt:\n");
    for (const QString &p : QCoreApplication::libraryPaths())
        std::printf("  %s\n", p.toLocal8Bit().constData());
    std::printf("\nQLibraryInfo::PluginsPath: %s\n",
        QLibraryInfo::path(QLibraryInfo::PluginsPath).toLocal8Bit().constData());
    return 0;
}
