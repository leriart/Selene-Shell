#pragma once

// LayerShellController -- Ndot-style real layer-shell wrapper for Selene.
//
// Owns a libwayland client display bound to the running compositor
// (Hyprland) and creates zwlr_layer_surface_v1 surfaces for the
// always-visible chrome (Bar, Island, Dock, ScreenCorners) and the
// on-demand panels (Launcher, Dashboard, etc). Each layer-shell
// surface renders into its own QWindow via Qt's QtWayland EGL
// integration (the QWindow's wl_surface is replaced with the
// layer-shell surface we hand to the compositor).
//
// The C++ side is small because QtWaylandClient handles the actual
// rendering + event delivery. We only manage the protocol binding
// and surface lifecycle. Qt's QWaylandClientExtensionTemplate is the
// official mechanism for registering custom Wayland protocols as
// QWaylandClientExtension subclasses; LayerShellController extends
// that.
//
// Threading: the Wayland display is owned by the QGuiApplication's
// thread (main). All public methods are called from QML/JS which runs
// on the main thread too. We pump events through Qt's normal loop.

#include <QObject>
#include <QQuickWindow>
#include <QRect>
#include <QString>
#include <QStringList>
#include <QVector>
#include <memory>

struct LayerShellState;

class LayerShellWindow;

class LayerShellController : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(QStringList availableLayers READ availableLayers CONSTANT)
public:
    explicit LayerShellController(QObject* parent = nullptr);
    ~LayerShellController() override;

    bool ready() const;
    QStringList availableLayers() const;

    // Create a layer-shell window backed by `window`. The window must
    // already be created (the layer-shell surface is set as its
    // native surface). `layer` is "background", "bottom", "overlay"
    // or "top". Returns nullptr on failure (compositor unsupported).
    Q_INVOKABLE LayerShellWindow* createWindow(QQuickWindow* window,
                                                const QString& layer,
                                                const QString& namespaceName);

signals:
    void readyChanged();

private:
    LayerShellState* d;
};

// A real layer-shell window. Wraps a QQuickWindow and binds it to a
// zwlr_layer_surface_v1. The compositor (Hyprland) decides the
// final placement via its layerrules; we just declare the anchor.
class LayerShellWindow : public QObject {
    Q_OBJECT
    Q_PROPERTY(QQuickWindow* window READ window CONSTANT)
    Q_PROPERTY(QString layer READ layer CONSTANT)
public:
    LayerShellWindow(QQuickWindow* window, const QString& layer,
                     const QString& namespaceName, QObject* parent = nullptr);
    ~LayerShellWindow() override;

    QQuickWindow* window() const;
    QString layer() const;

    // Reconfigure anchor / size. anchor is a comma-separated list of
    // edges: "top", "bottom", "left", "right". size is the requested
    // layer size in pixels (0,0 means match anchor / full screen).
    Q_INVOKABLE void configure(const QString& anchor, int width, int height);

    // Close the layer surface and hide the QWindow.
    Q_INVOKABLE void close();

private:
    struct Priv;
    std::unique_ptr<Priv> d;
};

Q_DECLARE_OPAQUE_POINTER(LayerShellWindow*)
