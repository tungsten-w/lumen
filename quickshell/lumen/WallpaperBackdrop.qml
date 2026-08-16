import QtQuick
import QtQuick.Effects

/// The wallpaper currently on screen, drawn the way rasi's
/// `background-image: url("/tmp/current_wallpaper.png", width)` draws it:
/// scaled so its width matches the widget, aspect ratio kept, pinned to the top
/// left, and whatever hangs off the bottom is clipped by the parent.
///
/// This is not `PreserveAspectCrop`: that would centre the overflow, and for a
/// 16:9 wallpaper in a strip this shallow the two show completely different
/// parts of the image.
///
/// Three settings move away from rofi's version: the zoom multiplies the width
/// it is drawn at — anything above 1 is cropped left and right rather than
/// squeezed — the position chooses which band of it the strip shows, and the
/// blur turns it into a frosted sheet for the search field to sit on.
Item {
    id: backdrop

    /// The widget being filled. Defaults to the parent, which is what both
    /// windows want.
    property Item area: parent

    /// The blur costs a full render pass of the header on every frame it
    /// changes, so it is only built when it is actually asked for.
    readonly property bool frosted: Style.backdrop.blur > 0 || Style.backdrop.dim > 0

    anchors.fill: area

    Image {
        id: image

        width: backdrop.width * Style.backdrop.zoom
        // implicitWidth is 0 until the file has been decoded; until then the
        // placeholder height keeps the binding harmless.
        height: implicitWidth > 0 ? width * (implicitHeight / implicitWidth) : backdrop.height
        fillMode: Image.PreserveAspectFit

        // Zooming grows the image around the middle horizontally, and slides it
        // under the strip vertically: 0 keeps the top edge, 1 the bottom one.
        x: (backdrop.width - width) / 2
        y: Math.min(0, backdrop.height - height) * Style.backdrop.position

        source: Style.wallpaper
        asynchronous: true
        cache: false
        // Wallpapers are 4K; decoding one at the width it is actually drawn at
        // keeps the window from holding 30 MB of pixels it will never show. It
        // has to be the *device* width — decode at the logical width and the
        // compositor upscales it again, which is visibly softer than rofi.
        sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)

        // Hidden while the effect below is drawing it, or it would show through
        // unblurred underneath.
        visible: !backdrop.frosted
        layer.enabled: backdrop.frosted

        // So that dragging the zoom or the framing reads as moving the image
        // rather than as the window being redrawn under you.
        Behavior on width {
            NumberAnimation {
                duration: Style.fadeDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: Style.fadeDuration
                easing.type: Easing.OutCubic
            }
        }

        // The picker's header is the largest thing on screen, so a hard cut when
        // the decode lands would be noticeable.
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Style.enterDuration
            }
        }
    }

    MultiEffect {
        source: image
        x: image.x
        y: image.y
        width: image.width
        height: image.height
        visible: backdrop.frosted

        blurEnabled: Style.backdrop.blur > 0
        blur: Style.backdrop.blur
        // The default blurMax is small enough that a full-strength blur still
        // reads as a photograph; this is the "frosted glass" range.
        blurMax: 64
        // Darkens rather than fades, so the palette's own background does not
        // wash through and change the colour of the header.
        brightness: -Style.backdrop.dim

        Behavior on blur {
            NumberAnimation {
                duration: Style.fadeDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on brightness {
            NumberAnimation {
                duration: Style.fadeDuration
                easing.type: Easing.OutCubic
            }
        }
    }
}
