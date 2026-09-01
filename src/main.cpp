#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>
#include <QtQuick/QQuickWindow>
#include <QtCore/QTimer>
#include <QtCore/QCommandLineParser>
#include <QtCore/QFile>
#include <QtCore/QDir>
#include <QtCore/QStandardPaths>
#include <QtNetwork/QLocalServer>
#include <QtNetwork/QLocalSocket>
#include <csignal>
#include <unistd.h>

int main(int argc, char* argv[])
{
    // Pre-flight: ensure we can actually talk to a Wayland compositor
    // before doing anything else. Without Hyprland running we cannot
    // draw, so exit cleanly with an actionable message instead of
    // crashing in QGuiApplication's ctor or hanging at exec().
    //
    // WAYLAND_DISPLAY can be either:
    //   - a plain socket name ("wayland-0", "wayland-1") -- in
    //     which case libwayland resolves it via XDG_RUNTIME_DIR
    //   - an absolute path ("/run/user/1000/wayland-1")
    // We mirror that by trying both interpretations.
    const auto probeWayland = []() -> bool {
        const QStringList candidates = {
            qEnvironmentVariable("WAYLAND_DISPLAY"),
            qEnvironmentVariable("WAYLAND_DISPLAY").split('/').last(),
        };
        const QString xdg = QStringLiteral("/run/user/%1").arg(getuid());
        const QStringList bases = {
            xdg,
            QDir::homePath() + QStringLiteral("/.cache"),
            QStringLiteral("/tmp"),
            QStringLiteral("."),
        };
        for (const QString& base : bases) {
            for (const QString& wd : candidates) {
                if (wd.isEmpty()) continue;
                QFileInfo fi(QDir(base).filePath(wd));
                if (fi.exists() && fi.isReadable()) {
                    if (fi.isAbsolute() || base == xdg) {
                        qputenv("WAYLAND_DISPLAY",
                                fi.absoluteFilePath().toUtf8());
                    }
                    return true;
                }
            }
        }
        return false;
    };
    if (!probeWayland()) {
        fprintf(stderr,
            "selene-shell: no Wayland compositor reachable.\n"
            "  - Is Hyprland running?\n"
            "  - Is WAYLAND_DISPLAY set to a valid socket?\n"
            "  - Run `hyprland` (or `Hyprland (Wayland)` from your\n"
            "    display manager) and try again.\n");
        return 1;
    }

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("selene-shell"));
    QGuiApplication::setDesktopFileName(QStringLiteral("selene-shell"));
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
        QStringLiteral("Open a panel before exiting: launcher, notif, walls, settings, audio, net, bt, sidebar, clipboard, picker, island, dashboard, overview, powermenu, binds (only meaningful with --screenshot)."),
        QStringLiteral("name"));
    const QCommandLineOption launcherQueryOpt(
        QStringLiteral("launcher-query"),
        QStringLiteral("Pre-fill the launcher's input when --show=launcher is used."),
        QStringLiteral("text"));
    const QCommandLineOption sizeOpt(
        QStringLiteral("size"),
        QStringLiteral("Render the window at <width>x<height> (default: 720x480)."),
        QStringLiteral("WxH"));
    const QCommandLineOption sendOpt(
        QStringLiteral("send"),
        QStringLiteral("Send <command> to the running shell instance over its local socket and exit "
                       "(e.g. --send=\"show powermenu\", --send=reload, --send=quit)."),
        QStringLiteral("command"));
    const QCommandLineOption presetOpt(
        QStringLiteral("preset"),
        QStringLiteral("Apply a theme preset on startup (default | sunset | midnight | monochrome). "
                       "Only meaningful with --screenshot."),
        QStringLiteral("name"));
    const QCommandLineOption animProfileOpt(
        QStringLiteral("anim-profile"),
        QStringLiteral("Set the animation profile (m3 | subtle | bouncy | off)."),
        QStringLiteral("name"));
    parser.addOption(screenshotOpt);
    parser.addOption(delayOpt);
    parser.addOption(showOpt);
    parser.addOption(launcherQueryOpt);
    parser.addOption(sizeOpt);
    parser.addOption(sendOpt);
    parser.addOption(presetOpt);
    parser.addOption(animProfileOpt);
    parser.process(app);

    // Live-control socket path, shared by the --send client mode and
    // the server mode below.
    const QString socketPath =
        QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
        + QStringLiteral("/selene-shell.sock");

    // Client mode: forward one command to the running instance.
    if (parser.isSet(sendOpt)) {
        QLocalSocket socket;
        socket.connectToServer(socketPath);
        if (!socket.waitForConnected(800)) {
            fprintf(stderr, "selene-shell: no running instance (%s)\n",
                    qPrintable(socket.errorString()));
            return 1;
        }
        socket.write(parser.value(sendOpt).toUtf8() + '\n');
        socket.flush();
        socket.waitForBytesWritten(800);
        socket.disconnectFromServer();
        return 0;
    }

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
    ctx->setContextProperty(QStringLiteral("__selenePreset"),
                            parser.value(presetOpt));
    ctx->setContextProperty(QStringLiteral("__seleneAnimProfile"),
                            parser.value(animProfileOpt));

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

    // -- Live control socket -------------------------------------------------
    // `selene <cmd>` (cli.sh) forwards commands here via --send. Each
    // connection carries a single line: "show <panel>", "reload", "quit".
    auto reloadShell = [&engine, url, &app]() {
        const auto roots = engine.rootObjects();
        for (QObject* obj : roots)
            obj->deleteLater();
        engine.clearComponentCache();
        // Let the deleteLater queue drain before recreating the window.
        QTimer::singleShot(60, &app, [&engine, url]() { engine.load(url); });
    };

    auto handleCommand = [&engine, &app, &reloadShell](const QString& line) {
        const QString cmd = line.trimmed();
        if (cmd.isEmpty())
            return;
        if (cmd == QLatin1String("quit")) {
            QCoreApplication::quit();
            return;
        }
        if (cmd == QLatin1String("reload")) {
            reloadShell();
            return;
        }
        if (cmd.startsWith(QLatin1String("show "))) {
            const QString panel = cmd.mid(5).trimmed();
            const auto roots = engine.rootObjects();
            if (!roots.isEmpty()) {
                QMetaObject::invokeMethod(
                    roots.first(), "applyScreenshotPanel",
                    Q_ARG(QString, panel));
            }
            return;
        }
        // Bare commands the shell handles outside of `show <panel>`.
        if (cmd == QLatin1String("wp-prev")
            || cmd == QLatin1String("wp-next")) {
            const auto roots = engine.rootObjects();
            if (!roots.isEmpty()) {
                QMetaObject::invokeMethod(
                    roots.first(), "applyScreenshotPanel",
                    Q_ARG(QString, cmd));
            }
            return;
        }
        // Multi-arg IPC: `apply-preset <name>`, `animation-profile <name>`,
        // `osd <kind> <value>`.
        if (cmd.startsWith(QLatin1String("apply-preset "))
            || cmd == QLatin1String("animation-profile")
                || cmd.startsWith(QLatin1String("animation-profile "))
            || cmd.startsWith(QLatin1String("osd"))) {
            const auto roots = engine.rootObjects();
            if (!roots.isEmpty()) {
                QMetaObject::invokeMethod(
                    roots.first(), "applyIpcCommand",
                    Q_ARG(QString, cmd));
            }
            return;
        }
    };

    QLocalServer ipcServer;
    QLocalServer::removeServer(socketPath); // stale socket from a crash
    if (ipcServer.listen(socketPath)) {
        QObject::connect(&ipcServer, &QLocalServer::newConnection,
                         &app, [&ipcServer, handleCommand]() {
            while (QLocalSocket* conn = ipcServer.nextPendingConnection()) {
                QObject::connect(conn, &QLocalSocket::readyRead,
                                 conn, [conn, handleCommand]() {
                    const auto lines = conn->readAll().split('\n');
                    for (const QByteArray& l : lines)
                        handleCommand(QString::fromUtf8(l));
                });
                QObject::connect(conn, &QLocalSocket::disconnected,
                                 conn, &QObject::deleteLater);
            }
        });
    }

    // SIGUSR1 = reload (cli.sh fallback when the socket is unreachable).
    // The handler only flips a flag; a Qt timer performs the reload on
    // the main thread.
    static volatile sig_atomic_t reloadRequested = 0;
    struct sigaction sa{};
    sa.sa_handler = [](int) { reloadRequested = 1; };
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGUSR1, &sa, nullptr);
    QTimer sigTimer;
    QObject::connect(&sigTimer, &QTimer::timeout, &app,
                     [&reloadShell]() {
        if (reloadRequested) {
            reloadRequested = 0;
            reloadShell();
        }
    });
    sigTimer.start(300);

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
