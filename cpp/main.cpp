#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>

int main(int argc, char* argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("selene-shell"));
    QGuiApplication::setOrganizationName(QStringLiteral("selene-shell"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("github.com"));

    QQmlApplicationEngine engine;

    const QUrl url(QStringLiteral(
        "qrc:/qt/qml/io/github/selene/shell/qml/Main.qml"));

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &app, [url](QObject* obj, const QUrl& objUrl) {
            if (!obj && url == objUrl) {
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    return app.exec();
}
