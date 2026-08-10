import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var notifier: null

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    onNotifierChanged: panelCore.reload()

    function toggle() {
        visible = !visible;
        if (visible && notifier) notifier.refresh_from_disk();
    }
    function open() {
        visible = true;
        if (notifier) notifier.refresh_from_disk();
    }
    function close() { visible = false; }

    function addSample() {
        if (!notifier) return;
        notifier.notify("selene", "Sample notification",
            "triggered from NotificationPanel.qml",
            1, "dialog-information");
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.barMargin
        width: 380

        color: Tokens.surface
        radius: Tokens.radiusLg
        border.color: Tokens.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Label {
                    text: "notifications"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Rectangle {
                    Layout.preferredHeight: 16
                    Layout.preferredWidth: 56
                    radius: 8
                    color: notifier && notifier.dbus_connected
                           ? Qt.darker(Tokens.success, 1.4)
                           : notifier && notifier.notifications_json !== "[]"
                             ? Qt.darker(Tokens.danger, 1.4)
                             : Tokens.surfaceAlt
                    border.color: notifier && notifier.dbus_connected
                                  ? Tokens.success : Tokens.border
                    border.width: 1
                    visible: notifier !== null

                    Label {
                        anchors.centerIn: parent
                        text: notifier && notifier.dbus_connected
                              ? "DBus ok" : "DBus ?"
                        color: notifier && notifier.dbus_connected
                               ? Tokens.success : Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: 44
                    radius: Tokens.radiusSm
                    color: notifier && notifier.unread_count > 0
                           ? Tokens.accent : "transparent"
                    border.color: Tokens.border
                    border.width: 1
                    visible: notifier !== null

                    Label {
                        anchors.centerIn: parent
                        text: notifier ? String(notifier.unread_count) : "0"
                        color: notifier && notifier.unread_count > 0 ? "#0e0f12" : Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontSm
                    }
                }

                Button {
                    text: notifier && notifier.dnd_enabled ? "DND on" : "DND off"
                    enabled: notifier !== null
                    onClicked: notifier.toggle_dnd()
                }

                Button {
                    text: notifier && notifier.game_mode ? "game on" : "game"
                    enabled: notifier !== null
                    onClicked: if (notifier) notifier.apply_game_mode(!notifier.game_mode)
                }

                ComboBox {
                    model: ["power-saver", "balanced", "performance"]
                    currentIndex: {
                        if (!notifier) return 1;
                        switch (notifier.power_profile) {
                        case "power-saver": return 0;
                        case "performance": return 2;
                        default: return 1;
                        }
                    }
                    enabled: notifier !== null
                    onActivated: function(i) {
                        if (notifier) notifier.apply_power_profile(
                            i === 0 ? "power-saver" : i === 2 ? "performance" : "balanced")
                    }
                    Layout.maximumWidth: 120
                }

                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            Item {
                id: panelCore
                property var entries: []
                property string loadError: ""

                function reload() {
                    if (!root.notifier) {
                        entries = [];
                        return;
                    }
                    let raw = root.notifier.notifications_json || "[]";
                    try {
                        entries = JSON.parse(raw) || [];
                        loadError = "";
                    } catch (e) {
                        entries = [];
                        loadError = String(e);
                    }
                }

                Connections {
                    target: root.notifier
                    function onNotifications_jsonChanged() { panelCore.reload(); }
                }
                Component.onCompleted: panelCore.reload()
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: Tokens.spacingXs

                    Label {
                        visible: panelCore.entries.length > 0 || (notifier && notifier.notifications_json === "[]")
                        text: "all caught up"
                        color: Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Tokens.spacingMd
                    }

                    Label {
                        visible: panelCore.entries.length === 0 && (!notifier || notifier.notifications_json !== "[]")
                        text: panelCore.loadError ? ("error: " + panelCore.loadError) : "no notifications"
                        color: Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Tokens.spacingMd
                    }

                    Repeater {
                        model: panelCore.entries

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            radius: Tokens.radiusSm
                            color: modelData.read ? "transparent"
                                   : Qt.darker(Tokens.accent, 5)
                            border.color: Tokens.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingSm
                                spacing: Tokens.spacingSm

                                Rectangle {
                                    Layout.preferredHeight: 8
                                    Layout.preferredWidth: 8
                                    radius: 4
                                    color: modelData.read ? Tokens.textDim : Tokens.accent
                                    Layout.alignment: Qt.AlignTop
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.title || ""
                                        color: Tokens.text
                                        font.family: Tokens.fontFamily
                                        font.pixelSize: Tokens.fontSm
                                        font.bold: !modelData.read
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.body || ""
                                        color: Tokens.textMuted
                                        font.family: Tokens.fontFamily
                                        font.pixelSize: Tokens.fontXs
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: (modelData.app_name || "?") + " · " +
                                              ("urg " + String(modelData.urgency || 0))
                                        color: Tokens.textDim
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontXs
                                    }

                                    RowLayout {
                                        visible: modelData.actions && modelData.actions.length >= 2
                                        spacing: Tokens.spacingXs

                                        Repeater {
                                            // Actions arrive as [key, label, key, label, ...]
                                            model: modelData.actions
                                                   ? Math.floor(modelData.actions.length / 2) : 0

                                            delegate: Rectangle {
                                                required property int index
                                                Layout.preferredHeight: 22
                                                Layout.preferredWidth: actionLabel.implicitWidth + 16
                                                radius: Tokens.radiusSm
                                                color: Tokens.surfaceAlt
                                                border.color: Tokens.accent
                                                border.width: 1

                                                Label {
                                                    id: actionLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.actions[index * 2 + 1] || "?"
                                                    color: Tokens.accent
                                                    font.family: Tokens.fontFamily
                                                    font.pixelSize: Tokens.fontXs
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: notifier.invoke_action(
                                                        modelData.id,
                                                        modelData.actions[index * 2])
                                                }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    onClicked: notifier.mark_read(modelData.id)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Button {
                    text: "+ sample"
                    onClicked: root.addSample()
                }

                Button {
                    text: "mark all read"
                    enabled: notifier !== null && notifier.unread_count > 0
                    onClicked: notifier.mark_all_read()
                }

                Button {
                    text: "clear"
                    enabled: notifier !== null
                    onClicked: notifier.clear()
                }

                Label {
                    text: "max"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }

                SpinBox {
                    from: 50; to: 2000; stepSize: 50
                    editable: true
                    value: notifier && notifier.history_max > 0 ? notifier.history_max : 200
                    enabled: notifier !== null
                    onValueModified: if (notifier) notifier.apply_history_max(value)
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
