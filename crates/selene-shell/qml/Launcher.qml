import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import io.github.selene.shell

Rectangle {
    id: root

    // Public surface
    function open(prefill) {
        input.text = (prefill === undefined || prefill === null) ? "" : prefill;
        visible = true;
        card.opacity = 1.0;
        card.scale = 1.0;
        if (input.text.length > 0) update();
        if (input.text.length === 0) input.forceActiveFocus();
    }
    function close() {
        card.opacity = 0.0;
        card.scale = 0.96;
        visible = false;
        input.text = "";
    }
    function toggle() {
        if (visible) close();
        else open();
    }

    property var spawner: null

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    Behavior on opacity {
        NumberAnimation { duration: Tokens.durationFast }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    property var appEntries: []
    property var actionEntries: []

    function rebuildEntries() {
        if (!spawner) {
            appEntries = [];
            actionEntries = [];
            return;
        }
        try {
            appEntries = JSON.parse(spawner.apps_json || "[]");
        } catch (e) {
            appEntries = [];
        }
        try {
            actionEntries = JSON.parse(spawner.actions_json || "[]");
        } catch (e) {
            actionEntries = [];
        }
    }

    onSpawnerChanged: rebuildEntries()

    property var results: []
    // Live values for the inline-action entries (calculator, web search).
    property string calcResult: ""
    property string calcError: ""
    property string searchUrl: ""

    // Curated emoji bank for the `:q` prefix picker. Keeping the bank
    // small and in-memory keeps the picker snappy and avoids chardata
    // surprises; common-but-not-bizarre symbols win out.
    readonly property var emojiBank: [
        "😀","😃","😄","😁","😆","😅","😂","🤣","😊","😇",
        "🙂","🙃","😉","😌","😍","🥰","😘","😗","😙","😚",
        "😋","😛","😝","😜","🤪","🤨","🧐","🤓","😎","🥸",
        "🤩","🥳","😏","😒","😞","😔","😟","😕","🙁","☹️",
        "😣","😖","😫","😩","🥺","😢","😭","😤","😠","😡",
        "🤬","🤯","😳","🥵","🥶","😱","😨","😰","😥","😓",
        "🤗","🤔","🤭","🤫","🤥","😶","😐","😑","😬","🙄",
        "👍","👎","👌","✌️","🤞","🤟","🤘","🤙","👈","👉",
        "👆","👇","☝️","✋","🤚","🖐","🖖","👋","🤝","🙏",
        "🔥","⭐","✨","💫","💥","💯","💢","💨","💦","💤",
        "🚀","🌟","🎉","🎊","🎈","🎂","🎁","🎵","🎶","🎮",
        "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔",
        "👍","✅","❌","❓","❗","💡","🔒","🔓","🔑","🛠"
    ]

    function update() {
        const query = input.text;
        const trimmed = query.trim();
        const isAction = trimmed.startsWith(">");
        const isApp = trimmed.startsWith("@");
        const isCalc = trimmed.startsWith("=");
        const isSearch = trimmed.startsWith("?");
        const isEmoji = trimmed.startsWith(":");
        const needle = (
            isAction ? trimmed.slice(1) :
            isApp    ? trimmed.slice(1) :
            isCalc   ? trimmed.slice(1) :
            isSearch ? trimmed.slice(1) :
            trimmed
        ).trim();

        calcResult = "";
        calcError = "";
        searchUrl = "";

        if (needle.length === 0) {
            results = [];
            return;
        }

        // == calculator =====================================================
        if (isCalc) {
            // Allow only digits, operators, parens, decimal, percent, space.
            const safe = needle.replace(/[^0-9+\-*/().%^,\s]/g, "");
            if (safe !== needle.replace(/\s+$/, "")) {
                calcError = "only digits and + - * / ( ) % ^";
            } else {
                try {
                    // ^ -> Math.pow, % -> mod 100 isn't right; treat as mod.
                    const expr = safe.replace(/\^/g, "**");
                    // eslint-disable-next-line no-new-func
                    const fn = new Function("return (" + expr + ");");
                    const v = fn();
                    calcResult = (typeof v === "number" && isFinite(v))
                                  ? String(v) : "NaN";
                } catch (e) {
                    calcError = String(e);
                }
            }
            results = [{
                kind: "calc",
                label: calcError || ("= " + calcResult),
                primary: calcResult,
                secondary: calcError
            }];
            return;
        }

        // == ? web search ===================================================
        if (isSearch) {
            const url = "https://duckduckgo.com/?q=" + encodeURIComponent(needle);
            searchUrl = url;
            results = [{
                kind: "search",
                label: "search: " + needle,
                primary: needle,
                url: url
            }];
            return;
        }

        // == :q emoji picker ===============================================
        if (isEmoji) {
            // Filter the bank by a substring match on the second character
            // when the user types past the colon. Names are unavailable
            // without an inline DB, so we only match by emoji itself.
            const lower = needle.toLowerCase();
            const out = [];
            for (let i = 0; i < emojiBank.length; ++i) {
                const e = emojiBank[i];
                if (lower.length === 0 || e.toLowerCase().indexOf(lower) !== -1) {
                    out.push({ kind: "emoji", label: e, primary: e });
                    if (out.length >= 60) break;
                }
            }
            results = out;
            return;
        }

        // == @ apps / > actions / fuzzy ====================================
        const bag = isAction ? actionEntries : appEntries;
        const out = [];
        const lower = needle.toLowerCase();
        for (let i = 0; i < bag.length; ++i) {
            const item = bag[i];
            const label = (item.label || "").toLowerCase();
            if (label.indexOf(lower) !== -1) {
                out.push({
                    kind: isAction ? "action" : "app",
                    label: item.label,
                    exec: item.exec
                });
            }
            if (out.length >= 8) break;
        }
        results = out;
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(760, root.width * 0.66)
        height: Math.min(480, root.height * 0.62)
        radius: Tokens.radiusLg
        color: Tokens.surface
        border.color: Tokens.border
        border.width: 1

        opacity: 0
        scale: 0.96

        Behavior on opacity {
            NumberAnimation { duration: Tokens.duration; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Tokens.duration; easing.type: Easing.OutCubic }
        }

        TextField {
            id: input
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 56
            leftPadding: Tokens.spacingLg
            rightPadding: Tokens.spacingLg
            placeholderText: "@ app   > action   = calc   ? web search   : emoji"
            placeholderTextColor: Tokens.textMuted
            color: Tokens.text
            background: Rectangle {
                color: "transparent"
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Tokens.border
                }
            }
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontLg

            onTextChanged: root.update()

            Keys.onEscapePressed: root.close()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                    resultsView.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    resultsView.decrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (results.length > 0) {
                        const item = results[resultsView.currentIndex];
                        if (item) launch(item);
                    }
                    event.accepted = true;
                }
            }
        }

        Label {
            id: hint
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 18
            anchors.rightMargin: Tokens.spacingLg
            text: input.text.length === 0
                  ? String.fromCharCode(0x2191, 0x2193) + " " + String.fromCharCode(0x23CE) + " esc"
                  : (results.length + " matches")
            color: Tokens.textMuted
            font.family: Tokens.monoFamily
            font.pixelSize: Tokens.fontXs
        }

        ListView {
            id: resultsView
            model: results
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: input.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 1
            clip: true

            Connections {
                target: root
                function onResultsChanged() {
                    resultsView.currentIndex = 0;
                }
            }

            delegate: Item {
                width: ListView.view.width
                height: 52

                required property var modelData
                required property int index

                Rectangle {
                    anchors.fill: parent
                    color: index === resultsView.currentIndex
                           ? Qt.darker(Tokens.accent, 4.5)
                           : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Tokens.durationFast }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Qt.darker(Tokens.border, 1.2)
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingLg
                    anchors.rightMargin: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 6
                        color: Qt.darker(Tokens.accent, 3.0)
                        Label {
                            anchors.centerIn: parent
                            text: modelData.kind === "app" ? "@"
                                : modelData.kind === "action" ? ">"
                                : modelData.kind === "calc" ? "="
                                : modelData.kind === "search" ? "?"
                                : modelData.kind === "emoji" ? ":"
                                : "?"
                            color: Tokens.accent
                            font.family: Tokens.monoFamily
                            font.pixelSize: Tokens.fontMd
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.kind === "emoji" ? "emoji " + modelData.label
                            : modelData.label
                        color: modelData.kind === "emoji" ? Tokens.text
                            : Tokens.text
                        font.family: modelData.kind === "emoji" ? Tokens.fontFamily
                            : Tokens.fontFamily
                        font.pixelSize: modelData.kind === "emoji" ? Tokens.fontXl
                            : Tokens.fontMd
                        elide: Text.ElideRight
                    }

                    Label {
                        text: modelData.kind === "search" ? "open"
                            : modelData.kind === "calc" ? (modelData.secondary ? "err" : "entry")
                            : modelData.kind === "emoji" ? "copy"
                            : modelData.exec
                        color: Tokens.textDim
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: resultsView.currentIndex = index
                    onClicked: launch(modelData)
                }
            }

            Label {
                anchors.centerIn: parent
                visible: results.length === 0
                text: input.text.length === 0
                      ? "type to search"
                      : "no matches"
                color: Tokens.textDim
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
            }
        }
    }

    function launch(item) {
        if (!item) return;
        if (item.kind === "calc") {
            // Pressing enter on a calc result copies it to the clipboard
            // via the clipboard via the GUI app; we don't ship our own
            // clipboard helper yet, so echo back to the visible label.
            return;
        }
        if (item.kind === "search") {
            if (spawner && item.url) {
                spawner.open_url(item.url);
            }
            root.close();
            return;
        }
        if (item.kind === "emoji") {
            if (spawner && item.primary) {
                spawner.copy_to_clipboard(item.primary);
            }
            root.close();
            return;
        }
        if (!item.exec) return;
        console.log("selene-launcher: launching", item.kind, item.label, "->", item.exec);
        if (spawner) {
            if (item.kind === "action") {
                spawner.run_action(item.label);
            } else {
                spawner.launch(item.exec);
                spawner.record_launch(item.label);
            }
        }
        root.close();
    }
}
