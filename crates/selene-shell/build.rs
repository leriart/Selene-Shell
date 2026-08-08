use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};
use qt_build_utils::{QResource, QResourceFile, QResources};

fn main() {
    let files: Vec<QmlFile> = vec![
        "qml/Main.qml".into(),
        QmlFile::from("qml/Tokens.qml").singleton(true),
        "qml/Bar.qml".into(),
        "qml/IslandPill.qml".into(),
        "qml/Launcher.qml".into(),
        "qml/NotificationPanel.qml".into(),
        "qml/WallpaperSurface.qml".into(),
        "qml/WallpaperPicker.qml".into(),
        "qml/SettingsPanel.qml".into(),
        "qml/AudioPanel.qml".into(),
        "qml/NetworkPanel.qml".into(),
        "qml/BluetoothPanel.qml".into(),
    ];

    // QML files are listed here so they get compiled into the binary's
    // resource bundle (qrc) and resolve at qrc:/qml/Foo.qml without a
    // runtime filesystem dependency.
    let qml_resources = QResources::new()
        .resource(QResource::new().file(
            QResourceFile::new("qml/Tokens.qml").alias("qml/Tokens.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/Bar.qml").alias("qml/Bar.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/IslandPill.qml").alias("qml/IslandPill.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/Launcher.qml").alias("qml/Launcher.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/NotificationPanel.qml")
                .alias("qml/NotificationPanel.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/WallpaperSurface.qml").alias("qml/WallpaperSurface.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/WallpaperPicker.qml").alias("qml/WallpaperPicker.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/SettingsPanel.qml").alias("qml/SettingsPanel.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/AudioPanel.qml").alias("qml/AudioPanel.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/NetworkPanel.qml").alias("qml/NetworkPanel.qml"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("qml/BluetoothPanel.qml").alias("qml/BluetoothPanel.qml"),
        ))
        // Bundled assets -- the .qml side references them as qrc:/assets/*.
        .resource(QResource::new().file(
            QResourceFile::new("../../assets/logo-dark.png").alias("assets/logo-dark.png"),
        ))
        .resource(QResource::new().file(
            QResourceFile::new("../../assets/logo-white.png").alias("assets/logo-white.png"),
        ));

    CxxQtBuilder::new_qml_module(
        QmlModule::new("io.github.selene.shell").qml_files(files),
    )
    .qt_module("Qml")
    .qrc_resources(qml_resources)
    .files([
        "src/audio.rs",
        "src/bluetooth.rs",
        "src/bridge.rs",
        "src/config.rs",
        "src/island.rs",
        "src/network.rs",
        "src/notifications.rs",
        "src/palette.rs",
        "src/spawner.rs",
        "src/visualizer.rs",
        "src/wallpaper.rs",
    ])
    .build();
}
