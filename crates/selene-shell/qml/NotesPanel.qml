import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// NotesPanel.qml -- persistent free-form notes (Brain_Shell +
// NothingLess port). Edit a single textarea; the Rust `Notes`
// QObject owns the JSON store and a `cards_json` list.
Rectangle {
    id: root

    property var notes: null
    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible ? close() : open(); }
    function open() {
        visible = true;
        if (notes) notes.refresh();
        forceActiveFocus();
    }
    function close() { visible = false; }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.barMargin * 4, 600)
        height: Math.min(parent.height - Tokens.barMargin * 4, 500)
        radius: Tokens.radiusLg
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g,
                       Tokens.surface.b, 0.95)
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.paddingLg
            spacing: Tokens.spacingMd

            // Header
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Notes"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            // Composer row.
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                TextField {
                    id: input
                    Layout.fillWidth: true
                    placeholderText: "Type a note and press Enter"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    onAccepted: addBtn.clicked()
                }
                Button {
                    id: addBtn
                    text: "+"
                    onClicked: {
                        if (input.text.length === 0 || !root.notes) return;
                        if (root.notes.add_note(input.text)) {
                            input.text = "";
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
            }

            // Notes list. We rebuild from `notes.cards_json` whenever
            // the property changes (cheap; tens of items max).
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                ScrollBar.vertical: ScrollBar {}

                property var entries: {
                    if (!root.notes) return [];
                    try { return JSON.parse(root.notes.notes_json || "[]"); }
                    catch (e) { return []; }
                }

                model: entries

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 40
                    radius: Tokens.radiusSm
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: Tokens.spacingSm

                        Label {
                            Layout.preferredWidth: 60
                            color: Tokens.textDim
                            font.family: Tokens.monoFamily
                            font.pixelSize: Tokens.fontXs
                            text: (modelData.ts || "").split("T")[1] || ""
                        }
                        Label {
                            Layout.fillWidth: true
                            color: Tokens.text
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            text: modelData.text
                            elide: Text.ElideRight
                        }
                        Button {
                            text: "\u2715"
                            onClicked: if (root.notes) root.notes.remove_note(index)
                        }
                    }
                }
            }

            Label {
                text: "Stored in ~/.local/share/selene/notes.json"
                color: Tokens.textDim
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
            }
        }
    }

    // Refresh on cards_json changes so the list reflects the latest
    // backend state without manual reload.
    Connections {
        target: root.notes
        function onNotes_jsonChanged() {
            // ListView re-binds via its `model` property which reads
            // root.notes.notes_json -- no manual repaint needed.
        }
    }

    Keys.onEscapePressed: root.close()
}
