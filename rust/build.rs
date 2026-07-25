use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("io.github.selene.shell").qml_file("../qml/Main.qml"),
    )
    .qt_module("Qml")
    .files(["src/bridge.rs"])
    .build();
}
