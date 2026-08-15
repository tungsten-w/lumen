import QtQuick

/// The wallpaper currently on screen, drawn the way rasi's
/// `background-image: url("/tmp/current_wallpaper.png", width)` draws it:
/// scaled so its width matches the widget, aspect ratio kept, pinned to the top
/// left, and whatever hangs off the bottom is clipped by the parent.
///
/// This is not `PreserveAspectCrop`: that would centre the overflow, and for a
/// 16:9 wallpaper in a strip this shallow the two show completely different
/// parts of the image.
Image {
    id: backdrop

    /// The widget being filled. Defaults to the parent, which is what both
    /// windows want.
    property Item area: parent

    x: 0
    y: 0
    width: area.width
    // implicitWidth is 0 until the file has been decoded; until then the
    // placeholder height keeps the binding harmless.
    height: implicitWidth > 0 ? width * (implicitHeight / implicitWidth) : area.height
    fillMode: Image.PreserveAspectFit

    source: Style.wallpaper
    asynchronous: true
    cache: false
    // Wallpapers are 4K; decoding one at the width it is actually drawn at keeps
    // the window from holding 30 MB of pixels it will never show. It has to be
    // the *device* width — decode at the logical width and the compositor
    // upscales it again, which is visibly softer than what rofi draws.
    sourceSize.width: Math.ceil(area.width * Screen.devicePixelRatio)

    // The picker's header is the largest thing on screen, so a hard cut when the
    // decode lands would be noticeable.
    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Style.enterDuration
        }
    }
}
