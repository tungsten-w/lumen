pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

/// Whole configurations, saved to a file and put back on demand.
///
/// One JSON file per preset in `~/.config/lumen/presets`, in the same shape as
/// `settings.json` itself — so a preset is something you can read, hand-edit,
/// send to someone, or drop into the folder straight out of a git repository.
///
/// `Default` is not a file. It is the rofi measurements Settings already
/// carries, which is what makes it the one preset that can never go missing.
Singleton {
    id: root

    readonly property string directory: `${Quickshell.env("HOME")}/.config/lumen/presets`
    readonly property string url: `file://${root.directory}`

    /// Names as shown, without the `.json`.
    property var names: []
    /// The last thing that happened, printed under the rows.
    property string status: ""
    /// Which preset is on its way in, so a second press cannot race the read.
    property string pending: ""

    function path(name: string): string {
        return `${root.directory}/${name}.json`;
    }

    function refresh() {
        const found = [];
        // A folder that is not there yet leaves the model listing whatever it
        // could reach instead — the first run showed `settings.json` from a
        // directory above. Nothing counts until it is looking where we asked.
        if (String(folder.folder) === root.url) {
            for (let i = 0; i < folder.count; i++) {
                found.push(String(folder.get(i, "fileName")).replace(/\.json$/, ""));
            }
        }
        root.names = found;
    }

    /// FolderListModel has no refresh of its own, and does not reliably notice
    /// our own writes. Pointing it away and back is what makes it look again.
    function rescan() {
        folder.folder = "";
        folder.folder = root.url;
        root.refresh();
    }

    /// Puts the rofi measurements back, with no file in the way.
    function applyDefault() {
        Settings.applyValues(Settings.defaults);
        root.status = "Default applied.";
    }

    function apply(name: string) {
        root.pending = name;
        const wanted = root.path(name);
        // Applying the same preset twice leaves the path alone, and a path that
        // does not change never reloads — so ask for the read outright.
        if (reader.path === wanted)
            reader.reload();
        else
            reader.path = wanted;
    }

    function save(name: string) {
        const clean = root.clean(name);
        if (!clean) {
            root.status = "That name has nothing in it.";
            return;
        }
        // A FileView takes a new path asynchronously, so a writer that is kept
        // around and re-pointed puts the second preset over the first — which is
        // exactly what it did. One writer per save has no path to change.
        // `setText` also makes the folders it needs, so the first preset works
        // on a machine that has never had a presets directory.
        const writer = pen.createObject(root, {
            path: root.path(clean)
        });
        writer.setText(JSON.stringify(Settings.snapshot(), null, 2) + "\n");
        writer.destroy(2000);
        root.status = `Saved as ${clean}.`;
        Qt.callLater(root.rescan);
    }

    function remove(name: string) {
        eraser.command = ["rm", "-f", root.path(name)];
        eraser.running = true;
        root.status = `Deleted ${name}.`;
    }

    /// A preset name becomes a filename, so it may not wander out of the folder
    /// or hide itself. Everything else is left alone: people name things with
    /// spaces and accents, and there is no reason to mangle that.
    function clean(name: string): string {
        return name.replace(/[\/\\]/g, " ") // no wandering out of the folder
        .replace(/\.+/g, ".")              // and no `...` left behind by it
        .replace(/^[.\s]+/, "")            // nor a leading dot, which hides it
        .replace(/\s+/g, " ").trim();
    }

    FolderListModel {
        id: folder

        folder: root.url
        nameFilters: ["*.json"]
        showDirs: false
        sortField: FolderListModel.Name

        onCountChanged: root.refresh()
    }

    FileView {
        id: reader

        printErrors: false // a preset deleted from under us is not a crash

        onLoaded: {
            const name = root.pending;
            root.pending = "";
            try {
                Settings.applyValues(JSON.parse(reader.text()));
                root.status = `${name} applied.`;
            } catch (error) {
                root.status = `${name} is not readable JSON.`;
            }
        }

        onLoadFailed: {
            root.status = `${root.pending} could not be read.`;
            root.pending = "";
        }
    }

    Component {
        id: pen

        FileView {
            atomicWrites: true
            printErrors: false
        }
    }

    Process {
        id: eraser

        onExited: Qt.callLater(root.rescan)
    }

    /// The directory has to be there before the model looks at it. `setText`
    /// makes it when a preset is saved, but the list is drawn long before that.
    Process {
        id: maker

        command: ["mkdir", "-p", root.directory]
        running: true

        onExited: root.rescan()
    }

    Component.onCompleted: root.refresh()
}
