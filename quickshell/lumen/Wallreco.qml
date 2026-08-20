pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// wallreco, driven from the settings panel.
///
/// It writes its tags into the filenames themselves — `sunset.png` becomes
/// `sunset-#orange-#warm-#sky.png` — because a launcher hands rofi bare
/// filenames, so whatever is in the name is what a search field can find. The
/// picker's own search reads them exactly the same way, which is why the panel
/// offers to run it rather than leaving it to a terminal.
///
/// https://github.com/tungsten-w/wallreco
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string directory: `${root.home}/Pictures/Wallpapers`

    /// Path to the binary, empty until the probe has found one. Resolved rather
    /// than assumed: the project installs it into `~/.local/bin`, which a
    /// shell started from a keybind does not always have on its PATH.
    property string binary: ""
    /// "looking", "yes" or "no" — the panel has three things to say, not two.
    property string presence: "looking"
    readonly property bool installed: root.presence === "yes"

    /// The last thing that happened, printed under the rows.
    property string status: ""
    /// Which job is running, so its own row can say so and the others go quiet.
    property string job: ""
    readonly property bool busy: runner.running

    function detect() {
        root.presence = "looking";
        probe.running = true;
    }

    /// Tags whatever has no tags yet. wallreco skips the files that already have
    /// some, so this is the one to reach for after dropping in new wallpapers.
    function tagMissing() {
        root.start("tag", [root.binary, root.directory]);
    }

    /// Strips every tag and computes them again in the same pass. It renames the
    /// whole collection, which is why the panel makes you press twice.
    function retag() {
        root.start("retag", [root.binary, "--retag", root.directory]);
    }

    /// The install the project documents: clone, build, drop the binary in
    /// `~/.local/bin`. It needs git and cargo, and it takes minutes.
    function install() {
        root.start("install", ["sh", "-c", "set -e; dir=$(mktemp -d); trap 'rm -rf \"$dir\"' EXIT; git clone --depth 1 https://github.com/tungsten-w/wallreco \"$dir\"; cd \"$dir\"; cargo build --release; install -Dm755 target/release/wallreco \"$HOME/.local/bin/wallreco\""]);
    }

    function start(what: string, command: var) {
        if (root.busy)
            return;
        root.job = what;
        root.status = "";
        runner.command = command;
        runner.running = true;
    }

    Process {
        id: probe

        // `command -v` covers an install that is on PATH; the explicit test
        // covers the documented one, which lands where a keybind may not look.
        command: ["sh", "-c", "command -v wallreco || { [ -x \"$HOME/.local/bin/wallreco\" ] && printf '%s\\n' \"$HOME/.local/bin/wallreco\"; }"]
        running: true

        stdout: StdioCollector {
            id: found

            onStreamFinished: {
                const path = found.text.trim().split("\n")[0] ?? "";
                root.binary = path;
                root.presence = path ? "yes" : "no";
            }
        }
    }

    Process {
        id: runner

        stdout: StdioCollector {
            id: output
        }
        stderr: StdioCollector {
            id: problem
        }

        onExited: (code, status) => {
            const what = root.job;
            root.job = "";
            if (code === 0) {
                // wallreco ends on a summary line; it is more useful than
                // anything this panel could invent.
                const summary = output.text.trim().split("\n").filter(line => line).pop() ?? "";
                if (what === "install") {
                    root.status = "Installed.";
                    root.detect();
                } else {
                    root.status = summary || (what === "retag" ? "Every tag recomputed." : "Nothing left untagged.");
                }
                return;
            }
            const reason = problem.text.trim().split("\n").filter(line => line).pop() ?? "";
            root.status = (what === "install" ? `Install failed (${code})` : `Failed (${code})`) + (reason ? ` — ${reason}` : "");
        }
    }
}
