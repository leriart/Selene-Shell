#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>
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
    const QCommandLineOption showOpt(
        QStringLiteral("show"),
        QStringLiteral("Open a panel before exiting: launcher, notif, walls, settings, audio, net, bt, sidebar, clipboard, picker, dashboard (only meaningful with --screenshot)."),
        QStringLiteral("name"));
    const QCommandLineOption launcherQueryOpt(
        QStringLiteral("launcher-query"),
        QStringLiteral("Pre-fill the launcher's input when --show=launcher is used."),
        QStringLiteral("text"));
    const QCommandLineOption sizeOpt(
        QStringLiteral("size"),
        QStringLiteral("Render the window at <width>x<height> (default: 720x480)."),
        QStringLiteral("WxH"));
    parser.addOption(screenshotOpt);
    parser.addOption(delayOpt);
    parser.addOption(showOpt);
    parser.addOption(launcherQueryOpt);
    parser.addOption(sizeOpt);
    parser.process(app);

    const QString screenshotPath = parser.value(screenshotOpt);
    const int delayMs = parser.value(delayOpt).toInt();
    const QString showPanel = parser.value(showOpt);
    const QString launcherQuery = parser.value(launcherQueryOpt);

    QSize renderSize(720, 480);
    if (parser.isSet(sizeOpt)) {
        const QStringList parts = parser.value(sizeOpt).split('x');
        if (parts.size() == 2) {
            bool okW = false, okH = false;
            const int w = parts[0].toInt(&okW);
            const int h = parts[1].toInt(&okH);
            if (okW && okH && w > 0 && h > 0) {
                renderSize = QSize(w, h);
            }
        }
    }

    QQmlApplicationEngine engine;

    // Tell QML which screenshot panel we want opened and the size to
    // render at, before load() resolves the bindings.
    auto* ctx = engine.rootContext();
    ctx->setContextProperty(QStringLiteral("__seleneScreenshotPanel"), showPanel);
    ctx->setContextProperty(QStringLiteral("__seleneLauncherQuery"), launcherQuery);
    ctx->setContextProperty(QStringLiteral("__seleneRenderSize"),
                            QVariant::fromValue(renderSize));

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

    // Apply the requested size to the root window so the rendered image
    // matches the docs expectation.
    if (auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().first())) {
        window->setWidth(renderSize.width());
        window->setHeight(renderSize.height());
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
