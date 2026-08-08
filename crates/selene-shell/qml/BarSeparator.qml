import QtQuick
import QtQuick.Layouts

// Hairline vertical separator tuned for the bar's 38px height and 8%
// white overlay. Used between the bar's slot groups.
Rectangle {
    Layout.preferredHeight: 18
    Layout.preferredWidth: 1
    color: Qt.rgba(1, 1, 1, 0.08)
    Layout.alignment: Qt.AlignVCenter
}
