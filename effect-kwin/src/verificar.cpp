#include <QCoreApplication>
#include <QPluginLoader>
#include <QJsonObject>
#include <cstdio>
int main(int argc, char **argv){
    QCoreApplication app(argc, argv);
    if (argc<2){ std::printf("falta ruta\n"); return 1; }
    QPluginLoader l(QString::fromLocal8Bit(argv[1]));
    const QJsonObject m = l.metaData();
    const bool ok = l.load();
    std::printf("puede cargarse : %s\n", ok?"SI":"NO");
    if(!ok) std::printf("error          : %s\n", l.errorString().toLocal8Bit().constData());
    std::printf("IID            : %s\n", m.value("IID").toString().toLocal8Bit().constData());
    const QJsonObject kp = m.value("KPlugin").toObject();
    std::printf("Id             : %s\n", kp.value("Id").toString().toLocal8Bit().constData());
    std::printf("Name           : %s\n", kp.value("Name").toString().toLocal8Bit().constData());
    return 0;
}
