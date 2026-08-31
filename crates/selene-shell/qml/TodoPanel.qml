import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// TodoPanel.qml -- 3-column kanban (Brain_Shell port).
//
// Three columns: todo / doing / done. Each card has the backend's
// global index (we search by ts+text). Persistence is owned by the
// Rust `TodoBoard` QObject; this QML just renders + dispatches.
Rectangle {
    id: root

    property var board: null
    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible ? close() : open(); }
    function open() {
        visible = true;
        if (board) board.refresh();
        forceActiveFocus();
    }
    function close() { visible = false; }

    // The full unfiltered card list; columns derive their views from
    // this in JS each time it changes.
    property var cards: []

    function rebuild() {
        if (!board) { cards = []; return; }
        try { cards = JSON.parse(board.cards_json || "[]"); }
        catch (e) { cards = []; }
    }

    function indexOf(card) {
        return cards.findIndex(function(c) {
            return c.ts === card.ts && c.text === card.text;
        });
    }

    onVisibleChanged: if (visible) rebuild()

    Connections {
        target: board
        function onCards_jsonChanged() { root.rebuild(); }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.barMargin * 4, 920)
        height: Math.min(parent.height - Tokens.barMargin * 4, 520)
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

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Todo Board"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: root.cards.length + " cards"
                    color: Tokens.textDim
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
            }

            // Three columns laid out side by side.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                Repeater {
                    model: [
                        { status: "todo",  label: "TO DO" },
                        { status: "doing", label: "DOING" },
                        { status: "done",  label: "DONE" }
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        property string status: modelData.status
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        Label {
                            text: modelData.label
                            color: Tokens.textMuted
                            font.family: Tokens.monoFamily
                            font.pixelSize: Tokens.fontXs
                            font.bold: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Tokens.radiusMd
                            color: Qt.rgba(0, 0, 0, 0.18)
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1

                            ListView {
                                id: columnList
                                anchors.fill: parent
                                anchors.margins: 8
                                clip: true
                                spacing: 6
                                ScrollBar.vertical: ScrollBar {}

                                model: root.cards.filter(function(c) {
                                    return c.status === parent.parent.status;
                                })

                                delegate: Rectangle {
                                    required property var modelData
                                    width: ListView.view.width
                                    height: 60
                                    radius: Tokens.radiusSm
                                    color: Qt.rgba(Tokens.bg.r, Tokens.bg.g,
                                                   Tokens.bg.b, 0.55)
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 2

                                        Label {
                                            text: modelData.text
                                            color: Tokens.text
                                            font.family: Tokens.fontFamily
                                            font.pixelSize: Tokens.fontSm
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Label {
                                                text: (modelData.ts || "").split("T")[1] || ""
                                                color: Tokens.textDim
                                                font.family: Tokens.monoFamily
                                                font.pixelSize: Tokens.fontXs
                                                Layout.fillWidth: true
                                            }
                                            Repeater {
                                                model: {
                                                    const buttons = status === "todo"
                                                        ? ["doing"]
                                                        : status === "doing"
                                                        ? ["done", "todo"]
                                                        : ["todo"];
                                                    return buttons;
                                                }
                                                delegate: Button {
                                                    required property string modelData
                                                    text: "\u2192 " + modelData
                                                    font.pixelSize: Tokens.fontXs
                                                    onClicked: {
                                                        if (!root.board) return;
                                                        const idx = root.indexOf(modelData0);
                                                        if (idx >= 0)
                                                            root.board.move_card(idx, modelData);
                                                    }
                                                    readonly property var modelData0:
                                                        parent.parent.parent.parent.modelData
                                                }
                                            }
                                            Button {
                                                text: "\u2715"
                                                font.pixelSize: Tokens.fontXs
                                                onClicked: {
                                                    if (!root.board) return;
                                                    const idx = root.indexOf(modelData);
                                                    if (idx >= 0)
                                                        root.board.remove_card(idx);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Add new card.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            TextField {
                                id: input
                                Layout.fillWidth: true
                                placeholderText: "add card"
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontSm
                                onAccepted: addBtn.clicked()
                            }
                            Button {
                                id: addBtn
                                text: "+"
                                onClicked: {
                                    if (input.text.length === 0 || !root.board) return;
                                    if (root.board.add_card(input.text, parent.parent.status))
                                        input.text = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root.close()
}
