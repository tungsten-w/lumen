pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// How the picker answers `lumen`.
///
/// rofi prints the selected line on stdout; a Quickshell config cannot, because
/// it is a long-lived shell process rather than a filter. So `lumen` passes the
/// path of a result file in `$LUMEN_RESULT`, we write the selection there and
/// quit, and `lumen` reads the file once we are gone. An empty file (or no file
/// at all) means "cancelled", which is what rofi's empty stdout means too.
Singleton {
    id: root

    /// Emitted once, as soon as a choice is made. Windows listen for it to play
    /// their closing animation while the file is already being written.
    signal closing

    property bool answered: false

    FileView {
        id: file
        path: Quickshell.env("LUMEN_RESULT") ?? ""
        printErrors: false // the file does not exist yet, and that is expected
        atomicWrites: true // `lumen` must never read a half-written selection
    }

    /// Hands `value` back to `lumen` and closes the picker.
    function accept(value: string) {
        if (root.answered)
            return;
        root.answered = true;

        // A slider moved in the last frame has not reached the settings file
        // yet; the write is deferred, and we are about to exit.
        Settings.flush();

        if (file.path !== "")
            file.setText(value);

        root.closing();
        quit.start();
    }

    /// Escape, or a click outside the window.
    function cancel() {
        root.accept("");
    }

    Timer {
        id: quit
        // Long enough for the closing animation to finish, and for the write
        // above to land — the file is what `lumen` is waiting on.
        interval: Style.exitDuration + 60
        onTriggered: Qt.quit()
    }
}
