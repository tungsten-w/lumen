import QtQuick
import QtQuick.Effects

/// One of the SVGs in `icons/`, painted in a colour of the palette.
///
/// The files are drawn in white and tinted here rather than being shipped in a
/// colour: multiplying a white source by the palette gives exactly the palette,
/// so one file follows every wallpaper instead of going grey against half of
/// them.
Item {
    id: icon

    /// File name in `icons/`, without the extension.
    required property string name
    property color color: Colors.foreground
    property real size: Style.textSize

    implicitWidth: icon.size
    implicitHeight: icon.size

    Image {
        id: source

        anchors.fill: parent
        source: `icons/${icon.name}.svg`
        fillMode: Image.PreserveAspectFit
        // Rasterised at the size it is drawn at, in device pixels — an SVG is
        // only sharp if it is asked for at the right resolution.
        sourceSize.width: Math.ceil(icon.size * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(icon.size * Screen.devicePixelRatio)

        // Drawn into a texture for the tint below rather than onto the window,
        // where it would show through in white.
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: source
        source: source
        colorization: 1
        colorizationColor: icon.color

        Behavior on colorizationColor {
            ColorAnimation {
                duration: Style.fadeDuration
            }
        }
    }
}
