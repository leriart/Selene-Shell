#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>
#include <QtQuick/QQuickWindow>
#include <QtCore/QTimer>
#include <QtCore/QCommandLineParser>

int main(int argc, char* argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("selene-shell"));
    QGuiApplication::setOrganizationName(QStringLiteral("selene-shell"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("github.com"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Selene -- a QML shell for Hyprland"));
    parser.addHelpOption();

    const QCommandLineOption screenshotOpt(
        QStringLiteral("screenshot"),
        QStringLiteral("Render for <ms> milliseconds, then save the window to <path> and exit. Useful for docs/CI."),
        QStringLiteral("path"));
    const QCommandLineOption delayOpt(
        QStringLiteral("delay"),
        QStringLiteral("Milliseconds to wait before capturing (default: 3000)."),
        QStringLiteral("ms"),
        QStringLiteral("3000"));
    parser.addOption(screenshotOpt);
    parser.addOption(delayOpt);
    parser.process(app);

    const QString screenshotPath = parser.value(screenshotOpt);
    const int delayMs = parser.value(delayOpt).toInt();

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

    if (!screenshotPath.isEmpty()) {
        QTimer::singleShot(delayMs, &app, [&app, &engine, screenshotPath]() {
            auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
            if (!window) {
                QCoreApplication::exit(2);
                return;
            }
            const QImage image = window->grabWindow();
            const bool saved = image.save(screenshotPath);
            if (!saved) {
                QCoreApplication::exit(3);
                return;
            }
            QCoreApplication::exit(0);
        });
    }

    return app.exec();
}
