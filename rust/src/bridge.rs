use core::pin::Pin;
use cxx_qt_lib::QString;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, greeting)]
        #[qproperty(i32, counter)]
        type Bridge = super::BridgeRust;

        #[qinvokable]
        fn increment(self: Pin<&mut Self>);

        #[qinvokable]
        fn greet(&self, name: &QString) -> QString;
    }
}

#[derive(Default)]
pub struct BridgeRust {
    greeting: QString,
    counter: i32,
}

impl qobject::Bridge {
    pub fn increment(self: Pin<&mut Self>) {
        let previous = *self.counter();
        let next = previous + 1;
        let msg = QString::from(format!("Selene step {next} -- bridge is live."));
        let mut this = self;
        this.as_mut().set_counter(next);
        this.as_mut().set_greeting(msg);
    }

    pub fn greet(&self, name: &QString) -> QString {
        let who = name.to_string();
        QString::from(format!("Hello, {who}. Welcome to Selene."))
    }
}
