use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};
use qt_build_utils::{QResource, QResourceFile, QResources};

fn main() {
    let files: Vec<QmlFile> = vec![
        "qml/Main.qml".into(),
        QmlFile::from("qml/Tokens.qml").singleton(true),
        "qml/Bar.qml".into(),
        "qml/IslandPill.qml".into(),
        "qml/Launcher.qml".into(),
    ];

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
        ));

    CxxQtBuilder::new_qml_module(
        QmlModule::new("io.github.selene.shell").qml_files(files),
    )
    .qt_module("Qml")
    .qrc_resources(qml_resources)
    .files(["src/bridge.rs", "src/island.rs", "src/spawner.rs"])
    .build();
}
