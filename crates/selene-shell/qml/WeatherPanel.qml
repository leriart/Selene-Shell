import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Weather card -- current conditions plus a mini forecast strip,
// backed by the Weather QObject (wttr.in). Used in the Dashboard's
// Weather tab; the Bar's mini-widget reuses `iconFor()` via a
// lightweight copy of the same mapping.
ColumnLayout {
    id: root

    property var weather: null

    spacing: Tokens.spacingMd

    // wttr.in ships WWO condition codes; map the common buckets onto
    // glyphs that read fine in any font. Night variants only matter
    // for the "clear" bucket.
    function iconFor(code, isDay) {
        if (code === 113) return isDay ? "\u2600" : "\u263D";      // clear
        if (code === 116) return "\u26C5";                          // partly cloudy
        if (code === 119 || code === 122) return "\u2601";          // cloudy
        if (code === 143 || code === 248 || code === 260) return "\u2592"; // fog
        if (code >= 176 && code <= 200) return "\u26C8";            // thundery
        if ((code >= 227 && code <= 230) || (code >= 320 && code <= 338)
            || (code >= 368 && code <= 395)) return "\u2744";       // snow
        if ((code >= 263 && code <= 318) || (code >= 350 && code <= 365))
            return "\u2614";                                        // rain
        return "\u2601";
    }

    property var _forecast: {
        if (!root.weather || !root.weather.forecast_json)
            return [];
        try {
            return JSON.parse(root.weather.forecast_json);
        } catch (e) {
            return [];
        }
    }

    // -- Current conditions ---------------------------------------------
    RowLayout {
        spacing: Tokens.spacingLg
        Layout.fillWidth: true

        Label {
            text: root.weather
                  ? root.iconFor(root.weather.weather_code, root.weather.is_day)
                  : "\u2601"
            color: Tokens.accent
            font.pixelSize: Tokens.fontXl * 2
        }

        ColumnLayout {
            spacing: 2
            Label {
                text: root.weather ? root.weather.temp.toFixed(0) + "\u00B0C" : "--"
                color: Tokens.text
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontXl
                font.bold: true
            }
            Label {
                text: root.weather && root.weather.weather_desc.length > 0
                      ? root.weather.weather_desc : "no data"
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
            }
        }

        Item { Layout.fillWidth: true }

        ColumnLayout {
            spacing: 2
            Label {
                text: root.weather
                      ? "\u2191 " + root.weather.temp_max.toFixed(0) + "\u00B0  \u2193 "
                        + root.weather.temp_min.toFixed(0) + "\u00B0"
                      : ""
                color: Tokens.textMuted
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
            }
            Label {
                text: root.weather
                      ? "wind " + root.weather.wind_speed.toFixed(0) + " km/h"
                      : ""
                color: Tokens.textMuted
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
            }
            Label {
                text: root.weather && root.weather.sunrise.length > 0
                      ? "\u2600 " + root.weather.sunrise + "  \u263D " + root.weather.sunset
                      : ""
                color: Tokens.textMuted
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
    }

    // -- Mini forecast strip ---------------------------------------------
    RowLayout {
        spacing: Tokens.spacingMd
        Layout.fillWidth: true

        Repeater {
            model: root._forecast
            delegate: ColumnLayout {
                required property var modelData
                required property int index
                spacing: 2
                Layout.fillWidth: true

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: index === 0 ? "today"
                                      : modelData.date.substring(5)
                    color: Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.iconFor(modelData.code, true)
                    color: Tokens.accent
                    font.pixelSize: Tokens.fontLg
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.max.toFixed(0) + "\u00B0 / "
                          + modelData.min.toFixed(0) + "\u00B0"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
            }
        }
    }

    Label {
        visible: !root.weather || !root.weather.available
        text: root.weather && root.weather.status.length > 0
              ? root.weather.status : "weather unavailable"
        color: Tokens.textDim
        font.family: Tokens.monoFamily
        font.pixelSize: Tokens.fontXs
    }

    Item { Layout.fillHeight: true }
}
