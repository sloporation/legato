#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

#include "library.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    // names the cache folder (QStandardPaths::CacheLocation), where the tag cache lives
    app.setApplicationName("legato");
    // the window's and the Dock's icon (branding/icon.svg, exported by branding/export.sh)
    app.setWindowIcon(QIcon(":/qt/qml/App/icons/legato.png"));
    // Basic: the controls are restyled in QML, which the native macOS and Windows styles do not allow.
    QQuickStyle::setStyle("Basic");

    QQmlApplicationEngine engine;
    engine.addImageProvider("cover", new CoverProvider);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(1); },
                     Qt::QueuedConnection);
    engine.loadFromModule("App", "Main");

    return app.exec();
}
