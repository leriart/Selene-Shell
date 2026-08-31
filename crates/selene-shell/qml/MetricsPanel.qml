import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// System metrics gauges -- CPU / RAM / GPU / disk with temperature
// readouts, backed by the SystemResources QObject. Rendered inside
// the Dashboard's Metrics tab but self-contained so it can be reused
// anywhere a `resources` backend is available.
ColumnLayout {
    id: root

    property var resources: null

    spacing: Tokens.spacingMd

    // One labelled progress row: NAME | bar | value (+ temp).
    component MetricRow: RowLayout {
        property string label: ""
        property real fraction: 0.0
        property string valueText: ""
        property string tempText: ""

        spacing: Tokens.spacingSm
        Layout.fillWidth: true

        Label {
            text: label
            color: Tokens.textMuted
            font.family: Tokens.monoFamily
            font.pixelSize: Tokens.fontXs
            Layout.preferredWidth: 42
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            radius: 4
            color: Tokens.surfaceAlt
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, fraction))
                radius: 4
                color: fraction > 0.9 ? Tokens.danger : Tokens.accent
                Behavior on width {
                    NumberAnimation {
                        duration: Tokens.animDuration("standard", "small")
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Tokens.animEasing("standard")
                    }
                }
            }
        }
        Label {
            text: valueText
            color: Tokens.text
            font.family: Tokens.monoFamily
            font.pixelSize: Tokens.fontXs
            Layout.preferredWidth: 92
            horizontalAlignment: Text.AlignRight
        }
        Label {
            text: tempText
            color: Tokens.textMuted
            font.family: Tokens.monoFamily
            font.pixelSize: Tokens.fontXs
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
            visible: tempText.length > 0
        }
    }

    Label {
        text: "System"
        color: Tokens.textMuted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSm
        font.bold: true
    }

    MetricRow {
        label: "CPU"
        fraction: root.resources ? root.resources.cpu_usage / 100.0 : 0
        valueText: root.resources ? root.resources.cpu_usage.toFixed(1) + "%" : "--"
        tempText: root.resources && root.resources.cpu_temp > 0
                  ? root.resources.cpu_temp + "\u00B0C" : ""
    }

    MetricRow {
        label: "RAM"
        fraction: root.resources ? root.resources.ram_usage / 100.0 : 0
        valueText: root.resources
                   ? (root.resources.ram_used / 1024.0).toFixed(1) + "/"
                     + (root.resources.ram_total / 1024.0).toFixed(1) + " GB"
                   : "--"
    }

    MetricRow {
        label: "GPU"
        visible: root.resources && root.resources.gpu_available
        fraction: root.resources ? root.resources.gpu_usage / 100.0 : 0
        valueText: root.resources ? root.resources.gpu_usage.toFixed(1) + "%" : "--"
        tempText: root.resources && root.resources.gpu_temp > 0
                  ? root.resources.gpu_temp + "\u00B0C" : ""
    }

    Label {
        text: "Disks"
        color: Tokens.textMuted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSm
        font.bold: true
    }

    // `disk_usage_json` is a var-backed parse; QString properties do
    // emit change signals, so a plain binding through a parser works.
    property var _disks: {
        if (!root.resources || !root.resources.disk_usage_json)
            return [];
        try {
            return JSON.parse(root.resources.disk_usage_json);
        } catch (e) {
            return [];
        }
    }

    Repeater {
        model: root._disks
        delegate: MetricRow {
            required property var modelData
            label: modelData.mount.length > 6
                   ? modelData.mount.substring(0, 6) : modelData.mount
            fraction: modelData.percent / 100.0
            valueText: modelData.used_gb.toFixed(0) + "/"
                       + modelData.size_gb.toFixed(0) + " GB"
        }
    }

    Label {
        visible: root._disks.length === 0
        text: "no disk data yet"
        color: Tokens.textDim
        font.family: Tokens.monoFamily
        font.pixelSize: Tokens.fontXs
    }

    Item { Layout.fillHeight: true }
}
