use chrono::{Datelike, Local, Timelike};
use rand::seq::SliceRandom;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::{Duration, SystemTime};

/// Largest edge of a generated thumbnail, in pixels.
///
/// The picker draws a thumbnail's icon box at 340px logical by default — see
/// Layout → Thumbnails → Zoom — and a display at scale 1.33 needs 453 physical
/// pixels of that at most. 512 leaves room for a higher zoom or a denser
/// screen without decoding pixels no window on this machine will ever show.
const THUMB_MAX_EDGE: u32 = 512;

/// awww is told `--transition-duration 0.7`, so that is exactly how long the
/// CPU-hungry theming tools should hold off before competing with it.
const TRANSITION_GUARD: Duration = Duration::from_millis(700);

// ══════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════

fn home_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME n'est pas défini"))
}

/// Where every window looks for the wallpaper that is currently up: the
/// picker's header, and the backdrop behind the mode menu. Always a flat
/// raster, whatever the source was — a GIF is stored here too, first frame
/// only. The real file, GIF or not, is what `current_wallpaper_path` below
/// hands to Quickshell so its backdrop can play one instead of freezing it.
const CURRENT_WALLPAPER: &str = "/tmp/current_wallpaper.png";

/// The wallpaper actually on screen, resolved from the symlink `apply_all`
/// keeps in `Pictures/Wallpapers` — canonicalised, so a relative or nested
/// symlink still comes back as one absolute, real path.
///
/// This is the file Quickshell is handed for the backdrop, kept apart from
/// `CURRENT_WALLPAPER` on purpose: that one is always a flat `.png`, which is
/// what `Image` alone can ever draw, while this keeps the true extension — a
/// GIF stays a GIF — so the Quickshell side can tell the two apart and play
/// the one that moves.
///
/// `None` for a symlink that is missing, dangling, or points outside a
/// filesystem this process can see — a fresh install, or a wallpaper deleted
/// since — and that is not an error: the caller simply has nothing extra to
/// hand over, the same as before this existed.
fn current_wallpaper_path(link: &Path) -> Option<PathBuf> {
    fs::canonicalize(link).ok()
}

/// Puts `CURRENT_WALLPAPER` back after a reboot.
///
/// `/tmp` is a tmpfs — it lives in RAM and is empty on every boot — so the copy
/// written when a wallpaper was chosen is gone by the next power-on, and the
/// menu comes up with no image behind it until something sets a wallpaper again.
///
/// The symlink in `Pictures/Wallpapers` is the pointer that does survive, so it
/// is what the temporary copy is rebuilt from. Only when the copy is missing: a
/// wallpaper change writes a fresh one, and re-copying the image on every launch
/// would be felt on a large one.
fn restore_current_wallpaper() {
    let shown = Path::new(CURRENT_WALLPAPER);
    if shown.exists() {
        return;
    }
    // `exists()` follows the link, so one left pointing at a wallpaper that has
    // since been deleted is skipped rather than copied as an error.
    let kept = home_dir().join("Pictures/Wallpapers/current_wallpaper.jpg");
    if kept.exists() {
        cache_wallpaper_still(&kept);
    }
}

/// Keep the menu's still-image cache as a real PNG, including when the chosen
/// wallpaper is a GIF or another format. The picker can separately use the
/// original path to animate GIF backgrounds.
fn cache_wallpaper_still(wallpaper: &Path) {
    if wallpaper
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("png"))
    {
        if let Err(error) = fs::copy(wallpaper, CURRENT_WALLPAPER) {
            eprintln!("Could not cache wallpaper {}: {error}", wallpaper.display());
        }
        return;
    }

    let temporary = format!("{CURRENT_WALLPAPER}.tmp.png");
    let mut first_frame = wallpaper.as_os_str().to_os_string();
    first_frame.push("[0]");
    let converted = Command::new("magick")
        .arg(first_frame)
        .arg(&temporary)
        .status()
        .is_ok_and(|status| status.success());
    if converted {
        if let Err(error) = fs::rename(&temporary, CURRENT_WALLPAPER) {
            eprintln!("Could not cache wallpaper {}: {error}", wallpaper.display());
            let _ = fs::remove_file(&temporary);
        }
    } else {
        eprintln!(
            "Could not convert wallpaper {} to PNG (ImageMagick needed)",
            wallpaper.display()
        );
        let _ = fs::remove_file(&temporary);
    }
}

/// Turns a `~` into your home.
///
/// The settings panel keeps a folder's path exactly as it was typed, because
/// `~/Pictures/anime` is what you want to read back and what still means
/// something on another machine. Nothing can open it, though: to the filesystem
/// that is a directory literally called `~`, and asking for it fails with
/// NotFound rather than with anything that reads like a mistake.
///
/// Done here rather than in the QML so it covers a settings file edited by hand
/// too — which the README invites you to do.
fn expand_home(path: &str) -> PathBuf {
    match path.strip_prefix("~/") {
        Some(rest) => home_dir().join(rest),
        None if path == "~" => home_dir(),
        None => PathBuf::from(path),
    }
}

fn parallelism() -> usize {
    thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
}

fn is_image(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| matches!(e.to_lowercase().as_str(), "jpg" | "png" | "gif" | "webp"))
        .unwrap_or(false)
}

/// Recursively collects image files under `dir`, skipping anything under `exclude`.
fn find_images(dir: &Path, exclude: &Path) -> Vec<PathBuf> {
    let mut result = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.starts_with(exclude) {
                continue;
            }
            // `entry.file_type()` comes from the readdir d_type, so it costs no
            // extra stat syscall the way `path.is_dir()` does. It does not follow
            // symlinks, so those fall back to the stat-ing check.
            let Ok(ft) = entry.file_type() else { continue };
            let is_dir = if ft.is_symlink() {
                path.is_dir()
            } else {
                ft.is_dir()
            };
            if is_dir {
                result.extend(find_images(&path, exclude));
            } else if is_image(&path) {
                result.push(path);
            }
        }
    }
    result
}

/// Reads `(width, height)` straight out of a PNG's IHDR chunk.
///
/// Used to spot thumbnails left over from an older, larger `THUMB_MAX_EDGE` so
/// they get regenerated instead of the grid decoding them at full size forever.
fn png_dimensions(path: &Path) -> Option<(u32, u32)> {
    let mut header = [0u8; 24];
    fs::File::open(path).ok()?.read_exact(&mut header).ok()?;
    if &header[..8] != b"\x89PNG\r\n\x1a\n" || &header[12..16] != b"IHDR" {
        return None;
    }
    let width = u32::from_be_bytes(header[16..20].try_into().ok()?);
    let height = u32::from_be_bytes(header[20..24].try_into().ok()?);
    Some((width, height))
}

/// True when `thumb` is missing, older than `img`, or was generated at a larger
/// size than we now target.
fn thumb_is_stale(thumb: &Path, img: &Path) -> bool {
    let (Ok(t), Ok(i)) = (thumb.metadata(), img.metadata()) else {
        return true;
    };
    let t_mtime = t.modified().unwrap_or(SystemTime::UNIX_EPOCH);
    let i_mtime = i.modified().unwrap_or(SystemTime::UNIX_EPOCH);
    if t_mtime < i_mtime {
        return true;
    }
    // `-thumbnail 512x512>` only ever shrinks, so a current thumbnail never
    // exceeds THUMB_MAX_EDGE on either edge.
    match png_dimensions(thumb) {
        Some((w, h)) => w > THUMB_MAX_EDGE || h > THUMB_MAX_EDGE,
        None => true,
    }
}

fn saison_for_month(month: u32) -> &'static str {
    match month {
        12 | 1 | 2 => "hiver",
        3..=5 => "printemps",
        6..=8 => "ete",
        _ => "automne",
    }
}

fn moment_for_hour(hour: u32) -> &'static str {
    if (7..18).contains(&hour) {
        "day"
    } else if (18..22).contains(&hour) {
        "sunset"
    } else {
        "night"
    }
}

fn get_saison() -> &'static str {
    saison_for_month(Local::now().month())
}

fn get_moment_journee() -> &'static str {
    moment_for_hour(Local::now().hour())
}

// ══════════════════════════════════════════════════════════════
// FONCTIONS
// ══════════════════════════════════════════════════════════════

/// Regenerates every stale thumbnail, one `magick` process per core.
///
/// `MAGICK_THREAD_LIMIT=1` matters as much as the fan-out here: left alone each
/// magick spins up its own OpenMP pool, and the resulting oversubscription costs
/// more than it buys once we are already running one process per core.
fn generate_thumbnails(pairs: &[(&PathBuf, PathBuf)]) {
    let todo: Vec<&(&PathBuf, PathBuf)> = pairs
        .iter()
        .filter(|(img, thumb)| thumb_is_stale(thumb, img))
        .collect();

    if todo.is_empty() {
        return;
    }

    let next = AtomicUsize::new(0);
    let workers = parallelism().min(todo.len());

    thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| {
                loop {
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    let Some((img, thumb)) = todo.get(index) else {
                        break;
                    };
                    let _ = Command::new("magick")
                        .env("MAGICK_THREAD_LIMIT", "1")
                        .arg(format!("{}[0]", img.display()))
                        .arg("-thumbnail")
                        .arg(format!("{THUMB_MAX_EDGE}x{THUMB_MAX_EDGE}>"))
                        .arg("-strip")
                        .arg(thumb)
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status();
                }
            });
        }
    });
}

/// Every wallpaper of `dir`, paired with its thumbnail and ready to display.
///
/// Both front-ends need the same list, so the scan, the sort and the thumbnail
/// refresh all happen here. An empty directory gives an empty list: the pickers
/// treat that as an error, but `--settings` is happy to show an empty grid.
fn wallpaper_entries(dir: &Path) -> Vec<(PathBuf, PathBuf)> {
    let thumb_dir = dir.join(".thumbnails");
    if fs::create_dir_all(&thumb_dir).is_err() {
        eprintln!("Erreur : impossible de créer {}.", thumb_dir.display());
        return Vec::new();
    }

    let mut images = find_images(dir, &thumb_dir);
    images.sort();

    let pairs: Vec<(&PathBuf, PathBuf)> = images
        .iter()
        .filter_map(|img| {
            let base_name = img.file_stem()?.to_string_lossy();
            Some((img, thumb_dir.join(format!("{base_name}.png"))))
        })
        .collect();

    generate_thumbnails(&pairs);

    pairs
        .into_iter()
        .map(|(img, thumb)| (img.clone(), thumb))
        .collect()
}

/// The wallpaper list as the Quickshell front-end reads it.
fn items_json(entries: &[(PathBuf, PathBuf)]) -> String {
    let items: Vec<serde_json::Value> = entries
        .iter()
        .filter_map(|(img, thumb)| {
            Some(serde_json::json!({
                "name": img.file_name()?.to_string_lossy(),
                "path": img.to_string_lossy(),
                "thumb": thumb.to_string_lossy(),
            }))
        })
        .collect();
    serde_json::json!({ "items": items }).to_string()
}

/// Both pickers stop here rather than opening on nothing.
fn require_entries(dir: &Path) -> Vec<(PathBuf, PathBuf)> {
    let entries = wallpaper_entries(dir);
    if entries.is_empty() {
        eprintln!("Erreur : Aucune image dans {}.", dir.display());
        std::process::exit(1);
    }
    entries
}

/// Shows the thumbnail grid for `dir` and waits for a wallpaper.
///
/// Answers with the full path rather than a bare filename, so wallpapers in
/// sub-directories work.
fn pick_with_quickshell(config: &Path, dir: &Path) -> PathBuf {
    let list = items_json(&require_entries(dir));

    let selected = quickshell_or_die(config, "picker", Some(&list));
    if selected.is_empty() {
        std::process::exit(0);
    }
    PathBuf::from(selected)
}

/// The thumbnail grid for one of your own folders, which answers with the mode
/// as well as the wallpaper.
///
/// A folder of your own has no dark or light about it — the same directory can
/// hold both — so the picker asks once you have chosen, and prefixes its answer
/// with what you said.
fn pick_from_folder(config: &Path, dir: &Path) -> Option<(PathBuf, bool)> {
    let list = items_json(&require_entries(dir));
    let answer = quickshell_or_die(config, "folder", Some(&list));
    if answer.is_empty() {
        std::process::exit(0);
    }

    // `dark:` or `light:`, then the path. Neither prefix holds a colon, so the
    // first one is the separator and the rest is the path however it is spelt.
    let (mode, path) = answer.split_once(':')?;
    Some((PathBuf::from(path), mode == "dark"))
}

/// apply a random wallpaper (season/hour)
fn pick_random(dir: &Path) -> Option<PathBuf> {
    if !dir.is_dir() {
        eprintln!("Erreur : {} n'existe pas.", dir.display());
        std::process::exit(1);
    }

    let images = find_images(dir, &dir.join(".thumbnails"));
    if images.is_empty() {
        eprintln!("Erreur : Aucune image dans {}.", dir.display());
        std::process::exit(1);
    }

    let mut rng = rand::thread_rng();
    images.choose(&mut rng).cloned()
}

fn update_json_field(path: &Path, key: &str, value: &str) {
    let Ok(content) = fs::read_to_string(path) else {
        return;
    };
    let Ok(mut json) = serde_json::from_str::<serde_json::Value>(&content) else {
        return;
    };
    json[key] = serde_json::Value::String(value.to_string());
    if let Ok(out) = serde_json::to_string_pretty(&json) {
        let _ = fs::write(path, out);
    }
}

/// Name of the spicetify theme in use, out of `config-xpui.ini`.
fn spicetify_theme(config: &str) -> Option<String> {
    config.lines().find_map(|line| {
        let (key, value) = line.split_once('=')?;
        (key.trim() == "current_theme").then(|| value.trim().to_string())
    })
}

/// The file holding the colours Spotify is themed with.
fn spicetify_colors() -> Option<PathBuf> {
    let config = fs::read_to_string(home_dir().join(".config/spicetify/config-xpui.ini")).ok()?;
    let theme = spicetify_theme(&config)?;
    let colors = home_dir().join(format!(".config/spicetify/Themes/{theme}/color.ini"));
    colors.is_file().then_some(colors)
}

/// What a run of `spicetify reload` actually did.
///
/// Live reload needs a connection to Spotify's DevTools. The first run after
/// Spotify starts — and any run after Spotify has updated itself — does not
/// reload anything: it turns DevTools on, restarts Spotify once, and says on
/// stdout to run the command again. Both passes exit 0 and neither takes a
/// flag, so the text is the only thing that tells them apart.
///
/// Left unread, that meant the first wallpaper of every session did nothing at
/// all to Spotify, which looks exactly like the command being broken.
///
/// From `spicetify-live_reload`, which is a fork: the wording is matched on the
/// shortest distinctive part of each line rather than on the whole of it.
#[derive(PartialEq, Debug)]
enum Reload {
    /// The colours are in Spotify.
    Pushed,
    /// It only set the connection up, and restarted Spotify doing so.
    SetUp,
    /// Neither — an older spicetify, a failure, an empty run.
    Unclear,
}

fn read_reload(said: &str) -> Reload {
    if said.contains("Reloaded theme colors") {
        Reload::Pushed
    } else if said.contains("run this command again") {
        Reload::SetUp
    } else {
        Reload::Unclear
    }
}

/// Pushes the new colours into Spotify, restarting it at most once.
///
/// Asks a second time when the first run only set the connection up. Exactly
/// once: a run that finds no live connection restarts Spotify to make one, so
/// asking again in a loop would be a loop of restarts rather than a retry.
fn reload_spotify() {
    let Ok(first) = Command::new("spicetify").arg("reload").output() else {
        eprintln!("spicetify introuvable.");
        return;
    };
    if read_reload(&String::from_utf8_lossy(&first.stdout)) != Reload::SetUp {
        return;
    }

    // Spotify is coming back up. The DevTools connection is not there the
    // instant the process is, so the wait is for the connection rather than
    // for the process — measured at a couple of seconds on this machine.
    wait_for_process("spotify", Duration::from_secs(20));
    thread::sleep(Duration::from_secs(3));

    let Ok(again) = Command::new("spicetify").arg("reload").output() else {
        return;
    };
    if read_reload(&String::from_utf8_lossy(&again.stdout)) != Reload::Pushed {
        eprintln!("spicetify n'a pas rechargé les couleurs; Spotify les aura au prochain fond.");
    }
}

/// Where Brave reads a managed policy from.
///
/// Root owns this file, and `lumen` runs from a keybind where a sudo prompt has
/// no terminal to appear in — so it is written only once someone has handed it
/// over, with `sudo chown $USER` on it. Silence when that has not been done is
/// deliberate: a wallpaper change is not the place to start asking for a
/// password.
const BRAVE_POLICY: &str = "/etc/brave/policies/managed/color.json";

/// The classic palette's background, as `#rrggbb`.
fn classic_background(wallust: bool) -> Option<String> {
    let file = if wallust {
        ".cache/wallust/colors.json"
    } else {
        ".cache/wal/colors.json"
    };
    let raw = fs::read_to_string(home_dir().join(file)).ok()?;
    let json: serde_json::Value = serde_json::from_str(&raw).ok()?;
    let colour = json.get("special")?.get("background")?.as_str()?;
    (colour.len() == 7 && colour.starts_with('#')).then(|| colour.to_string())
}

/// Run each classic provider used by either window. Older settings without a
/// classic source keep the previous pywal behavior.
fn classic_generators(settings: Option<&serde_json::Value>) -> (bool, bool) {
    let colors = settings.and_then(|value| value.get("colors"));
    let picker = colors
        .and_then(|value| value.get("palette"))
        .and_then(|value| value.as_str())
        .unwrap_or("pywal");
    let menu = colors
        .and_then(|value| value.get("menuPalette"))
        .and_then(|value| value.as_str())
        .unwrap_or("pywal");
    let wallust = picker == "wallust" || menu == "wallust";
    let pywal = picker == "pywal" || menu == "pywal" || !wallust;
    (pywal, wallust)
}

fn selected_classic_generators() -> (bool, bool) {
    let settings = fs::read_to_string(home_dir().join(".config/lumen/settings.json"))
        .ok()
        .and_then(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok());
    classic_generators(settings.as_ref())
}

/// The policy Brave is handed, for one colour.
fn brave_policy(colour: &str) -> String {
    // `BrowserColorScheme` is kept because it costs nothing and was already in
    // the file — though it does not appear in the binary's policy names the way
    // `BrowserThemeColor` does, so it may well be ignored.
    format!("{{\"BrowserThemeColor\": \"{colour}\", \"BrowserColorScheme\": \"device\"}}\n")
}

/// Repaints a running Brave to match the wallpaper, without closing anything.
///
/// Brave has no theme command — but Chromium reads enterprise policy out of
/// /etc/brave/policies/managed, and `--refresh-platform-policy` tells a running
/// instance to read it again: a second process finds the first through
/// Chromium's ProcessSingleton, passes the message and exits.
/// `--no-startup-window` stops it opening anything on the way. The window you
/// are looking at never closes, no tab is lost, and it takes about a tenth of a
/// second.
///
/// Only the accent is ours to set. This is Material You seeded from one colour,
/// not a stylesheet.
fn reload_brave(wallust: bool) {
    if !is_running("brave") {
        return;
    }
    let Some(colour) = classic_background(wallust) else {
        return;
    };

    let wanted = brave_policy(&colour);
    // Nothing to announce when nothing changed, and a policy refresh is not
    // free — it makes every open window repaint.
    if fs::read_to_string(BRAVE_POLICY).is_ok_and(|held| held == wanted) {
        return;
    }
    if fs::write(BRAVE_POLICY, &wanted).is_err() {
        eprintln!(
            "Brave : {BRAVE_POLICY} n'est pas accessible en écriture.\n\
             Une fois pour toutes : sudo chown $USER {BRAVE_POLICY}"
        );
        return;
    }

    let _ = Command::new("brave")
        .args(["--refresh-platform-policy", "--no-startup-window"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// Blocks until `name` is running, and says whether it turned up.
fn wait_for_process(name: &str, timeout: Duration) -> bool {
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        if is_running(name) {
            return true;
        }
        thread::sleep(Duration::from_millis(200));
    }
    false
}

/// Blocks until `path` has been written since `since`, and says whether it was.
fn wait_for_write(path: &Path, since: SystemTime, timeout: Duration) -> bool {
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        let written = path
            .metadata()
            .and_then(|meta| meta.modified())
            .map(|modified| modified > since)
            .unwrap_or(false);
        if written {
            // The write we just saw start may still be in flight.
            thread::sleep(Duration::from_millis(200));
            return true;
        }
        thread::sleep(Duration::from_millis(100));
    }
    false
}

/// `pgrep -x` without the fork: walks /proc and compares against comm, which is
/// the same truncated-to-15-bytes name pgrep itself matches on.
fn is_running(process_name: &str) -> bool {
    let Ok(entries) = fs::read_dir("/proc") else {
        return false;
    };
    let needle = process_name.as_bytes();
    let needle = &needle[..needle.len().min(15)];

    for entry in entries.flatten() {
        let name = entry.file_name();
        if !name.to_string_lossy().bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        if let Ok(comm) = fs::read(entry.path().join("comm"))
            && comm.strip_suffix(b"\n").unwrap_or(&comm) == needle
        {
            return true;
        }
    }
    false
}

/// Apply wallpaper and themes.
fn apply_all(wallpaper: &Path, dark: bool) {
    // Everything the theming tools write from here on is newer than this.
    let started = SystemTime::now();
    let wal_flags: Vec<&str> = if dark { vec!["-q"] } else { vec!["-l", "-q"] };
    let wallust_palette = if dark { "dark" } else { "light" };
    let (run_pywal, run_wallust) = selected_classic_generators();
    let matugen_mode = if dark { "dark" } else { "light" };
    let (obs_base, obs_theme, relaunch_obs) = if dark {
        ("dark", "obsidian", true)
    } else {
        ("light", "moonstone", false)
    };

    // ── independent tasks launched in parallel ──────────────────
    let mut handles = Vec::new();

    // Nothing below depends on these, so they no longer delay the wallpaper.
    // `-x` rather than `-f`: matching the whole command line would also kill
    // anything that merely mentions feh, this script's own launcher included.
    handles.push(thread::spawn(|| {
        let _ = Command::new("pkill").args(["-x", "feh"]).status();
    }));

    // set cursor theme based on mode (dark/light)
    handles.push(thread::spawn(move || {
        let cursor = if dark {
            "Bibata-Modern-Classic"
        } else {
            "Bibata-Modern-Ice"
        };
        let _ = Command::new("hyprctl")
            .args(["setcursor", cursor, "24"])
            .status();
    }));

    // Wallpaper — kicked off first so the transition starts as early as possible
    let _ = Command::new("awww")
        .arg("img")
        .arg(wallpaper)
        .args([
            "--transition-type",
            "random",
            "--transition-fps",
            "60",
            "--transition-duration",
            "0.7",
        ])
        .status();

    {
        let wallpaper = wallpaper.to_path_buf();
        handles.push(thread::spawn(move || {
            let current_link = home_dir().join("Pictures/Wallpapers/current_wallpaper.jpg");
            let _ = fs::remove_file(&current_link);
            #[cfg(unix)]
            {
                let _ = std::os::unix::fs::symlink(&wallpaper, &current_link);
            }
        }));
    }

    // Classic palette provider(s). Both run only when the menu and picker use
    // different classic sources.
    {
        let wallpaper = wallpaper.to_path_buf();
        let wal_flags: Vec<String> = wal_flags.into_iter().map(String::from).collect();
        handles.push(thread::spawn(move || {
            thread::sleep(TRANSITION_GUARD); // stay off the CPU while awww animates
            if run_pywal {
                let status = Command::new("wal")
                    .arg("-i")
                    .arg(&wallpaper)
                    .args(&wal_flags)
                    .status();
                if !status.map(|s| s.success()).unwrap_or(false) {
                    eprintln!("Erreur pywal.");
                }
            }
            if run_wallust {
                let status = Command::new("wallust")
                    .arg("run")
                    .arg(&wallpaper)
                    .args(["--palette", wallust_palette])
                    .status();
                if !status.map(|s| s.success()).unwrap_or(false) {
                    eprintln!("Erreur wallust.");
                } else {
                    if let Some(hook) = std::env::var_os("LUMEN_WALLUST_HOOK") {
                        let hook_status = Command::new(hook)
                            .env("LUMEN_DARK_MODE", if dark { "dark" } else { "light" })
                            .env("LUMEN_WALLPAPER", &wallpaper)
                            .status();
                        if !hook_status.map(|s| s.success()).unwrap_or(false) {
                            eprintln!("Le hook Wallust a échoué.");
                        }
                    }
                    let cache = home_dir().join(".cache/wallust");
                    if !cache.join("colors-rofi-dark.rasi").is_file()
                        || !cache.join("colors.json").is_file()
                    {
                        eprintln!("Wallust: configurez les templates Lumen dans ~/.config/wallust/wallust.toml.");
                    }
                }
            }
            reload_brave(run_wallust);
        }));
    }

    // Copy /tmp (thumbnails for hyprpanel/hyprlock...)
    {
        let wallpaper = wallpaper.to_path_buf();
        handles.push(thread::spawn(move || {
            cache_wallpaper_still(&wallpaper);
        }));
    }

    // Matugen (gtk/rofi/tmux/neovim theming)
    {
        let wallpaper = wallpaper.to_path_buf();
        let matugen_mode = matugen_mode.to_string();
        handles.push(thread::spawn(move || {
            thread::sleep(TRANSITION_GUARD); // stay off the CPU while awww animates
            let _ = Command::new("matugen")
                .arg("image")
                .arg(&wallpaper)
                .args(["--mode", &matugen_mode])
                .arg("-c")
                .arg(home_dir().join(".config/matugen/config.toml"))
                .args(["--prefer", "saturation", "-q"])
                .status();
        }));
    }

    // Noctalia + Spicetify
    {
        let wallpaper = wallpaper.to_path_buf();
        let skip_noctalia = std::env::var("LUMEN_SKIP_NOCTALIA").as_deref() == Ok("1");
        handles.push(thread::spawn(move || {
            if !skip_noctalia {
                if !is_running("noctalia") {
                    let _ = Command::new("nohup")
                        .args(["noctalia", "-d"])
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn();
                    thread::sleep(Duration::from_secs(3));
                }

                let mode = if dark { "dark" } else { "light" };
                let _ = Command::new("noctalia")
                    .args(["msg", "theme-mode-set", mode])
                    .status();
                let _ = Command::new("noctalia")
                    .args(["msg", "wallpaper-set"])
                    .arg(&wallpaper)
                    .status();
            }

            if is_running("spotify") {
                // Spotify's colours are not ours to write: Noctalia's own
                // spicetify template writes them, and it does so a good while
                // after `wallpaper-set` has returned — measured at three seconds
                // against a reload that used to fire at two. Reloading early
                // hands Spotify the palette of the *previous* wallpaper, which
                // looks exactly like the command never ran.
                //
                // So we wait for the file itself rather than for a duration.
                match spicetify_colors() {
                    Some(colors) => {
                        wait_for_write(&colors, started, Duration::from_secs(15));
                    }
                    None => thread::sleep(Duration::from_secs(3)),
                }
                reload_spotify();
            }
        }));
    }

    // Ulauncher
    handles.push(thread::spawn(|| {
        let _ = Command::new("pkill").args(["-f", "ulauncher"]).status();
    }));

    // Obsidian
    {
        let obs_base = obs_base.to_string();
        let obs_theme = obs_theme.to_string();
        handles.push(thread::spawn(move || {
            let vault_app = home_dir().join("Documents/Obsidian Vault/.obsidian/app.json");
            let vault_appear =
                home_dir().join("Documents/Obsidian Vault/.obsidian/appearance.json");
            update_json_field(&vault_app, "baseTheme", &obs_base);
            update_json_field(&vault_appear, "theme", &obs_theme);

            if relaunch_obs {
                let flatpak = Command::new("nohup")
                    .args(["flatpak", "run", "md.obsidian.Obsidian"])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
                if flatpak.is_err() {
                    let _ = Command::new("nohup")
                        .arg("obsidian")
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn();
                }
            }
        }));
    }

    for handle in handles {
        let _ = handle.join();
    }
}

// ══════════════════════════════════════════════════════════════
// MAIN MENU
// ══════════════════════════════════════════════════════════════

#[derive(Clone, PartialEq, Debug)]
enum Mode {
    Dark,
    Light,
    Heure,
    Saison,
    /// A folder of your own, added in the settings panel and shown in the mode
    /// menu beside the four above.
    ///
    /// The menu answers with the path itself rather than with a name, so this
    /// binary never has to know what your categories are — it opens the picker
    /// on whatever it was handed. That is the whole of the feature on this side:
    /// no settings file to read, no format to keep in step with the QML.
    Folder(PathBuf),
}

impl Mode {
    /// The menu answers with a plain name, which is what makes its QML
    /// readable — this is the only spelling there has ever been to accept.
    fn parse(answer: &str) -> Option<Mode> {
        // Everything after the first colon is the path, colons and all: only the
        // prefix is ours to read.
        if let Some(path) = answer.strip_prefix("folder:")
            && !path.is_empty()
        {
            return Some(Mode::Folder(expand_home(path)));
        }
        match answer {
            "dark" => Some(Mode::Dark),
            "light" => Some(Mode::Light),
            "time" => Some(Mode::Heure),
            "season" => Some(Mode::Saison),
            _ => None,
        }
    }
}

/// Finds `shell.qml`, or says why it cannot and stops.
///
/// Quickshell draws every prompt lumen has — the menu, the picker, the settings
/// panel — so a config that cannot be found, or a `qs` that is not on the PATH,
/// leaves nothing left to try.
fn quickshell_config() -> PathBuf {
    let candidates = [
        std::env::var_os("LUMEN_QS_CONFIG").map(PathBuf::from),
        Some(home_dir().join(".config/quickshell/lumen/shell.qml")),
        // Running straight from a clone of the dotfiles repository.
        Some(home_dir().join(".config/lumen/quickshell/lumen/shell.qml")),
    ];

    let Some(config) = candidates.into_iter().flatten().find(|path| path.is_file()) else {
        eprintln!("Erreur : aucune configuration Quickshell trouvée.");
        eprintln!(
            "Voir « Installation » dans le README, ou pointez LUMEN_QS_CONFIG sur shell.qml."
        );
        std::process::exit(1);
    };

    if !has_command("qs") {
        eprintln!("Erreur : `qs` (Quickshell) est introuvable sur le PATH.");
        eprintln!("Voir « Installation » dans le README pour l'installer.");
        std::process::exit(1);
    }

    config
}

fn has_command(name: &str) -> bool {
    std::env::var_os("PATH")
        .is_some_and(|path| std::env::split_paths(&path).any(|dir| dir.join(name).is_file()))
}

/// A scratch file to talk to the Quickshell process with. XDG_RUNTIME_DIR is a
/// user-owned tmpfs, so the wallpaper list never reaches the disk, and the pid
/// keeps two `lumen` runs from reading each other's answer.
fn runtime_file(name: &str) -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("lumen-{name}-{}", std::process::id()))
}

/// Shows one Quickshell prompt and waits for it.
///
/// `Some("")` is a cancelled prompt — Escape, or a click outside the window.
/// `None` means `qs` itself never got as far as answering; see
/// `quickshell_or_die`, which is what every caller actually uses.
fn run_quickshell(config: &Path, mode: &str, items: Option<&str>) -> Option<String> {
    let result = runtime_file("result");
    // A leftover answer from an earlier run would be indistinguishable from
    // this one's, and the picker only writes the file when something is chosen.
    let _ = fs::remove_file(&result);

    let items_file = items.map(|json| {
        let path = runtime_file("items");
        let _ = fs::write(&path, json);
        path
    });

    let mut command = Command::new("qs");
    command
        .arg("-p")
        .arg(config)
        .env("LUMEN_MODE", mode)
        .env("LUMEN_RESULT", &result);
    // Every window that draws a backdrop wants this, so it goes out on every
    // launch rather than only the ones that show one.
    if let Some(path) =
        current_wallpaper_path(&home_dir().join("Pictures/Wallpapers/current_wallpaper.jpg"))
    {
        command.env("LUMEN_CURRENT_WALLPAPER", path);
    }
    if let Some(path) = &items_file {
        command.env("LUMEN_ITEMS", path);
    }
    let status = command.status();

    let answer = fs::read_to_string(&result)
        .unwrap_or_default()
        .trim()
        .to_string();
    let _ = fs::remove_file(&result);
    if let Some(path) = items_file {
        let _ = fs::remove_file(path);
    }

    if !status.map(|s| s.success()).unwrap_or(false) {
        return None;
    }
    Some(answer)
}

/// `run_quickshell`, with nothing left to fall back to.
///
/// A `qs` that will not answer once it is the only front-end there is means the
/// prompt the user asked for cannot be shown at all — a hard stop with a
/// message beats a silent do-nothing that looks like the keybind did nothing.
fn quickshell_or_die(config: &Path, mode: &str, items: Option<&str>) -> String {
    run_quickshell(config, mode, items).unwrap_or_else(|| {
        eprintln!("Erreur : Quickshell n'a pas répondu.");
        std::process::exit(1);
    })
}

/// Random wallpaper for the time of day it is, dark once the sun is down.
///
/// This is the mode menu's third entry, and what `lumen --time` runs on its own:
/// no prompt, so a timer can call it.
fn apply_time_of_day() {
    let moment = get_moment_journee();
    if let Some(wp) =
        pick_random(&home_dir().join(format!("Pictures/Wallpapers/season-time/{moment}")))
    {
        apply_all(&wp, moment == "night" || moment == "sunset");
    }
}

/// Random wallpaper for the season it is. Always light, as the menu has it.
fn apply_season() {
    let saison = get_saison();
    if let Some(wp) =
        pick_random(&home_dir().join(format!("Pictures/Wallpapers/season-time/{saison}")))
    {
        apply_all(&wp, false);
    }
}

/// Path of the lock the unattended modes hold.
fn auto_lock() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("lumen-auto.lock")
}

/// True when `pid` is a `lumen`, so a recycled pid is never killed by mistake.
fn is_lumen(pid: u32) -> bool {
    fs::read(format!("/proc/{pid}/comm"))
        .map(|comm| comm.strip_suffix(b"\n").unwrap_or(&comm) == b"lumen")
        .unwrap_or(false)
}

/// Makes room for an unattended run.
///
/// `--time` is made to be called by a timer, and a timer that fires while the
/// previous run is still painting leaves pywal and matugen writing over each
/// other's palette. The older run goes first, along with the tools it started —
/// they outlive their parent, so killing it is not enough.
fn take_auto_lock() {
    let lock = auto_lock();

    if let Ok(text) = fs::read_to_string(&lock)
        && let Ok(pid) = text.trim().parse::<u32>()
        && pid != std::process::id()
        && is_lumen(pid)
    {
        let pid = pid.to_string();
        let _ = Command::new("pkill").args(["-9", "-P", &pid]).status();
        let _ = Command::new("kill").args(["-9", &pid]).status();
    }

    for tool in ["wal -i", "wallust run", "matugen image"] {
        let _ = Command::new("pkill").args(["-9", "-f", tool]).status();
    }

    let _ = fs::write(&lock, std::process::id().to_string());
}

/// Shows the mode menu and waits for one of the four entries.
fn choose_mode(config: &Path) -> Option<Mode> {
    Mode::parse(&quickshell_or_die(config, "menu", None))
}

/// `lumen --settings` — the settings panel, with the picker beside it as a live
/// preview of what every value does.
///
/// Nothing can be picked from that preview, so opening the settings can never
/// change the wallpaper by accident; the panel writes to
/// `~/.config/lumen/settings.json` as you move a slider, and both prompts read
/// it from then on. The same panel opens over a real picker with Ctrl+,.
fn open_settings(config: &Path) {
    // The panel has nowhere to write if this is a fresh install.
    let _ = fs::create_dir_all(home_dir().join(".config/lumen"));

    let list = items_json(&wallpaper_entries(
        &home_dir().join("Pictures/Wallpapers/dark"),
    ));
    quickshell_or_die(config, "settings", Some(&list));
}

/// Deletes thumbnails whose source image is gone (renamed or removed), which
/// otherwise accumulate in the cache forever. Returns how many were freed.
fn prune_thumbnails(thumb_dir: &Path, keep: &[(&PathBuf, PathBuf)]) -> (usize, u64) {
    let live: std::collections::HashSet<&Path> =
        keep.iter().map(|(_, thumb)| thumb.as_path()).collect();

    let Ok(entries) = fs::read_dir(thumb_dir) else {
        return (0, 0);
    };
    let (mut count, mut bytes) = (0, 0);
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "png") || live.contains(path.as_path()) {
            continue;
        }
        let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
        if fs::remove_file(&path).is_ok() {
            count += 1;
            bytes += size;
        }
    }
    (count, bytes)
}

/// Builds every missing thumbnail for a directory without showing the picker,
/// so the cache can be warmed ahead of time (`lumen --thumbs`).
fn warm_thumbnails(dir: &Path) {
    let thumb_dir = dir.join(".thumbnails");
    if fs::create_dir_all(&thumb_dir).is_err() {
        return;
    }
    let images = find_images(dir, &thumb_dir);
    let pairs: Vec<(&PathBuf, PathBuf)> = images
        .iter()
        .filter_map(|img| {
            let base_name = img.file_stem()?.to_string_lossy();
            Some((img, thumb_dir.join(format!("{base_name}.png"))))
        })
        .collect();
    generate_thumbnails(&pairs);
    let (pruned, bytes) = prune_thumbnails(&thumb_dir, &pairs);
    println!(
        "{} : {} images, {} orphelins supprimés ({:.1} Mo)",
        dir.display(),
        pairs.len(),
        pruned,
        bytes as f64 / 1e6
    );
}

const USAGE: &str = "\
lumen — one wallpaper, and the whole desktop follows.

Usage:
  lumen                  the menu: dark, light, time of day, season
  lumen --time           a random wallpaper for the time of day, no prompt
  lumen --season         a random wallpaper for the season, no prompt
  lumen --settings       the picker's settings: shape, motion, layout, color
  lumen --thumbs [DIR…]  rebuild the thumbnails without showing anything
  lumen --help           this

The picker's settings also open from inside it, with Ctrl+, or by typing
`settings` into its search field. The mode menu keeps its own panel, on its cog
or on the same Ctrl+,.";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|a| a == "--help" || a == "-h") {
        println!("{USAGE}");
        return;
    }
    // Nothing below draws before this: /tmp does not survive a reboot, and the
    // menu is the first thing that wants the image back.
    restore_current_wallpaper();
    // Unattended: no prompt at all, for a timer or a keybind of its own.
    if let Some(mode) = args.first().and_then(|arg| match arg.as_str() {
        "--time" => Some(Mode::Heure),
        "--season" => Some(Mode::Saison),
        _ => None,
    }) {
        take_auto_lock();
        match mode {
            Mode::Heure => apply_time_of_day(),
            _ => apply_season(),
        }
        let _ = fs::remove_file(auto_lock());
        return;
    }
    if args.first().is_some_and(|a| a == "--settings") {
        open_settings(&quickshell_config());
        return;
    }
    // An unknown flag is a typo, not a wallpaper directory: say so rather than
    // opening the menu as if nothing had been asked for.
    if args
        .first()
        .is_some_and(|a| a.starts_with('-') && a != "--thumbs")
    {
        eprintln!("Unknown option: {}\n\n{USAGE}", args[0]);
        std::process::exit(2);
    }
    if args.first().is_some_and(|a| a == "--thumbs") {
        let dirs: Vec<PathBuf> = if args.len() > 1 {
            args[1..].iter().map(PathBuf::from).collect()
        } else {
            let base = home_dir().join("Pictures/Wallpapers");
            vec![base.join("dark"), base.join("light")]
        };
        for dir in dirs {
            warm_thumbnails(&dir);
        }
        return;
    }

    let _ = Command::new("nohup")
        .arg(home_dir().join(".config/.scripts/wallpaper_recognition.sh"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();

    let config = quickshell_config();

    match choose_mode(&config) {
        // Dark — thumbnail picker
        Some(Mode::Dark) => {
            let wp = pick_with_quickshell(&config, &home_dir().join("Pictures/Wallpapers/dark"));
            apply_all(&wp, true);
        }
        // Light — thumbnail picker
        Some(Mode::Light) => {
            let wp = pick_with_quickshell(&config, &home_dir().join("Pictures/Wallpapers/light"));
            apply_all(&wp, false);
        }
        // Heure — random, dark if night/sunset
        Some(Mode::Heure) => apply_time_of_day(),
        // Saison — random, light
        Some(Mode::Saison) => apply_season(),
        // One of your own folders — the grid, then the mode you asked for.
        Some(Mode::Folder(dir)) => {
            if let Some((wp, dark)) = pick_from_folder(&config, &dir) {
                apply_all(&wp, dark);
            }
        }
        // Cancelled.
        None => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classic_provider_selection() {
        assert_eq!(classic_generators(None), (true, false));
        let settings = serde_json::json!({"colors": {
            "palette": "wallust", "menuPalette": "wallust"
        }});
        assert_eq!(classic_generators(Some(&settings)), (false, true));
        let mixed = serde_json::json!({"colors": {
            "palette": "wallust", "menuPalette": "pywal"
        }});
        assert_eq!(classic_generators(Some(&mixed)), (true, true));
        let material = serde_json::json!({"colors": {
            "palette": "matugen", "menuPalette": "noctalia"
        }});
        assert_eq!(classic_generators(Some(&material)), (true, false));
    }

    #[test]
    fn saison_matches_bash_case() {
        for m in [12, 1, 2] {
            assert_eq!(saison_for_month(m), "hiver");
        }
        for m in 3..=5 {
            assert_eq!(saison_for_month(m), "printemps");
        }
        for m in 6..=8 {
            assert_eq!(saison_for_month(m), "ete");
        }
        for m in 9..=11 {
            assert_eq!(saison_for_month(m), "automne");
        }
    }

    #[test]
    fn moment_matches_bash_case() {
        for h in 0..7 {
            assert_eq!(moment_for_hour(h), "night");
        }
        for h in 7..18 {
            assert_eq!(moment_for_hour(h), "day");
        }
        for h in 18..22 {
            assert_eq!(moment_for_hour(h), "sunset");
        }
        for h in 22..24 {
            assert_eq!(moment_for_hour(h), "night");
        }
    }

    #[test]
    fn the_brave_policy_is_the_json_brave_expects() {
        // Byte for byte what was in /etc/brave/policies/managed by hand, so a
        // run changes the colour and nothing else about the file.
        assert_eq!(
            brave_policy("#1c2027"),
            "{\"BrowserThemeColor\": \"#1c2027\", \"BrowserColorScheme\": \"device\"}\n"
        );
        // And it has to parse, or Brave ignores the lot in silence.
        let held: serde_json::Value = serde_json::from_str(&brave_policy("#100b1b")).unwrap();
        assert_eq!(held["BrowserThemeColor"], "#100b1b");
    }

    #[test]
    fn reload_output_is_read_correctly() {
        // Verbatim from the strings inside `spicetify vbeta-live-reload`. One
        // line each on purpose: a `\` continuation in a Rust literal eats the
        // indentation of the next line as well, which welded "run" to "this" and
        // left this test checking a sentence no spicetify would ever print.
        let pushed = "success  Reloaded theme colors without restarting Spotify";
        let set_up = "Applied theme. Spotify is now set up for live reload; run this command again next time to update colors without restarting.";
        let restarting = " No live connection to Spotify found. Enabling DevTools and restarting once to set it up...";

        assert_eq!(read_reload(pushed), Reload::Pushed);
        assert_eq!(read_reload(set_up), Reload::SetUp);
        // The whole first pass, both lines together, reads the same way.
        assert_eq!(
            read_reload(&format!("{restarting}\n{set_up}")),
            Reload::SetUp
        );

        // The two must never be confused: the whole point is asking again after
        // one of them and not after the other.
        assert_ne!(read_reload(pushed), read_reload(set_up));

        // An older spicetify with no live reload at all, and a silent run.
        assert_eq!(read_reload("Applied theme"), Reload::Unclear);
        assert_eq!(read_reload(""), Reload::Unclear);
    }

    #[test]
    fn spicetify_theme_is_read_from_the_ini() {
        let config = "\
[Setting]
spotify_path          = /opt/spotify
current_theme          = Comfy
color_scheme           = Comfy
";
        assert_eq!(spicetify_theme(config).as_deref(), Some("Comfy"));
        // A file without the key, or an empty one, must not guess a theme.
        assert_eq!(spicetify_theme("color_scheme = Comfy"), None);
        assert_eq!(spicetify_theme(""), None);
    }

    #[test]
    fn wait_for_write_sees_a_write_and_gives_up_without_one() {
        let dir = std::env::temp_dir().join(format!("lumen_wait_{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("color.ini");
        fs::write(&file, b"old").unwrap();

        // Nothing writes it: we wait, and say so.
        let since = SystemTime::now();
        assert!(!wait_for_write(&file, since, Duration::from_millis(300)));

        // Written while we wait: picked up.
        let writer = {
            let file = file.clone();
            thread::spawn(move || {
                thread::sleep(Duration::from_millis(150));
                fs::write(&file, b"new").unwrap();
            })
        };
        assert!(wait_for_write(&file, since, Duration::from_secs(5)));
        writer.join().unwrap();

        // A file that is not there at all is not worth waiting for forever.
        assert!(!wait_for_write(
            &dir.join("gone.ini"),
            since,
            Duration::from_millis(200)
        ));

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn mode_parses_what_the_quickshell_menu_writes() {
        assert_eq!(Mode::parse("dark"), Some(Mode::Dark));
        assert_eq!(Mode::parse("light"), Some(Mode::Light));
        assert_eq!(Mode::parse("time"), Some(Mode::Heure));
        assert_eq!(Mode::parse("season"), Some(Mode::Saison));

        // A cancelled prompt, and anything that is none of the above.
        assert_eq!(Mode::parse(""), None);
        assert_eq!(Mode::parse("whatever"), None);
    }

    #[test]
    fn current_wallpaper_path_resolves_a_real_symlink() {
        let dir = std::env::temp_dir().join(format!("lumen_link_{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();

        let real = dir.join("sunset-#orange.gif");
        fs::write(&real, b"x").unwrap();
        let link = dir.join("current_wallpaper.jpg");
        std::os::unix::fs::symlink(&real, &link).unwrap();

        assert_eq!(
            current_wallpaper_path(&link),
            Some(fs::canonicalize(&real).unwrap())
        );

        // A wallpaper renamed or deleted out from under the link.
        fs::remove_file(&real).unwrap();
        assert_eq!(current_wallpaper_path(&link), None);

        // No link at all — a fresh install, before anything has been applied.
        assert_eq!(current_wallpaper_path(&dir.join("nothing_here")), None);

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_tilde_becomes_your_home() {
        let home = home_dir();
        assert_eq!(expand_home("~/Pictures/anime"), home.join("Pictures/anime"));
        assert_eq!(expand_home("~"), home);
        // Only a leading `~/` is ours: these are paths, not shell words.
        assert_eq!(expand_home("/srv/~/x"), PathBuf::from("/srv/~/x"));
        assert_eq!(expand_home("~notauser/x"), PathBuf::from("~notauser/x"));
        assert_eq!(expand_home("/home/you/x"), PathBuf::from("/home/you/x"));
    }

    #[test]
    fn a_folder_from_the_panel_is_openable() {
        // What the panel stores, and what the menu therefore answers with. It
        // has to come back out as something read_dir can actually open.
        let answer = "folder:~/Pictures/anime/";
        let Some(Mode::Folder(dir)) = Mode::parse(answer) else {
            panic!("not parsed as a folder");
        };
        assert!(dir.is_absolute(), "{} is not absolute", dir.display());
        assert!(!dir.to_string_lossy().contains('~'));
        assert_eq!(dir, home_dir().join("Pictures/anime/"));
    }

    #[test]
    fn mode_parses_a_folder_of_your_own() {
        assert_eq!(
            Mode::parse("folder:/home/you/Pictures/anime"),
            Some(Mode::Folder(PathBuf::from("/home/you/Pictures/anime")))
        );

        // A path may hold colons, spaces and a `#` — wallpaper folders in this
        // collection do. Only the first colon is ours.
        assert_eq!(
            Mode::parse("folder:/home/you/Pictures/odd: name/#red"),
            Some(Mode::Folder(PathBuf::from(
                "/home/you/Pictures/odd: name/#red"
            )))
        );

        // Nothing after the prefix is not a folder.
        assert_eq!(Mode::parse("folder:"), None);

        // And the four the menu has always answered are untouched.
        assert_eq!(Mode::parse("dark"), Some(Mode::Dark));
        assert_eq!(Mode::parse("season"), Some(Mode::Saison));
    }

    #[test]
    fn a_folder_answer_carries_the_mode_and_keeps_the_path_whole() {
        // What pick_from_folder splits: the picker prefixes its answer.
        let split = |answer: &str| -> Option<(PathBuf, bool)> {
            let (mode, path) = answer.split_once(':')?;
            Some((PathBuf::from(path), mode == "dark"))
        };

        assert_eq!(
            split("dark:/home/you/a.png"),
            Some((PathBuf::from("/home/you/a.png"), true))
        );
        assert_eq!(
            split("light:/home/you/a.png"),
            Some((PathBuf::from("/home/you/a.png"), false))
        );
        // A wallpaper named with a colon still arrives whole.
        assert_eq!(
            split("dark:/home/you/10:30 sunset-#orange.png"),
            Some((PathBuf::from("/home/you/10:30 sunset-#orange.png"), true))
        );
    }

    #[test]
    fn is_image_matches_bash_iname_globs() {
        assert!(is_image(Path::new("foo.jpg")));
        assert!(is_image(Path::new("foo.JPG")));
        assert!(is_image(Path::new("foo.png")));
        assert!(is_image(Path::new("foo.gif")));
        assert!(is_image(Path::new("foo.WEBP")));
        // the original find only matches these four extensions, no jpeg
        assert!(!is_image(Path::new("foo.jpeg")));
        assert!(!is_image(Path::new("foo.txt")));
        assert!(!is_image(Path::new("foo")));
    }

    #[test]
    fn png_dimensions_reads_ihdr() {
        let dir = std::env::temp_dir().join(format!("lumen_png_{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();

        // 8-byte signature, 4-byte length, "IHDR", then width/height big-endian.
        let mut png = Vec::from(*b"\x89PNG\r\n\x1a\n");
        png.extend_from_slice(&13u32.to_be_bytes());
        png.extend_from_slice(b"IHDR");
        png.extend_from_slice(&900u32.to_be_bytes());
        png.extend_from_slice(&506u32.to_be_bytes());
        let good = dir.join("good.png");
        fs::write(&good, &png).unwrap();
        assert_eq!(png_dimensions(&good), Some((900, 506)));

        let bad = dir.join("bad.png");
        fs::write(&bad, b"not a png at all really").unwrap();
        assert_eq!(png_dimensions(&bad), None);

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn thumb_is_stale_detects_oversized_and_outdated_thumbnails() {
        let dir = std::env::temp_dir().join(format!("lumen_stale_{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();

        let write_png = |path: &Path, w: u32, h: u32| {
            let mut png = Vec::from(*b"\x89PNG\r\n\x1a\n");
            png.extend_from_slice(&13u32.to_be_bytes());
            png.extend_from_slice(b"IHDR");
            png.extend_from_slice(&w.to_be_bytes());
            png.extend_from_slice(&h.to_be_bytes());
            fs::write(path, &png).unwrap();
        };

        let img = dir.join("wall.jpg");
        fs::write(&img, b"x").unwrap();

        // Missing thumbnail.
        let missing = dir.join("missing.png");
        assert!(thumb_is_stale(&missing, &img));

        // Legacy 900px thumbnail, newer than the source but too large to keep.
        let oversized = dir.join("oversized.png");
        write_png(&oversized, 900, 506);
        assert!(thumb_is_stale(&oversized, &img));

        // Correctly sized thumbnail, newer than the source.
        let fresh = dir.join("fresh.png");
        write_png(&fresh, THUMB_MAX_EDGE, 288);
        assert!(!thumb_is_stale(&fresh, &img));

        // A thumbnail smaller than the cap (source was small) is still fine.
        let small = dir.join("small.png");
        write_png(&small, 320, 200);
        assert!(!thumb_is_stale(&small, &img));

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn prune_thumbnails_removes_only_orphans() {
        let dir = std::env::temp_dir().join(format!("lumen_prune_{}", std::process::id()));
        let thumb_dir = dir.join(".thumbnails");
        fs::create_dir_all(&thumb_dir).unwrap();

        let img = dir.join("kept.jpg");
        fs::write(&img, b"x").unwrap();
        let kept = thumb_dir.join("kept.png");
        fs::write(&kept, b"1234567890").unwrap();
        let orphan = thumb_dir.join("deleted-wallpaper.png");
        fs::write(&orphan, b"12345").unwrap();
        // Non-png files in the cache dir must be left alone.
        let stray = thumb_dir.join("notes.txt");
        fs::write(&stray, b"x").unwrap();

        let pairs = vec![(&img, kept.clone())];
        let (count, bytes) = prune_thumbnails(&thumb_dir, &pairs);

        assert_eq!(count, 1);
        assert_eq!(bytes, 5);
        assert!(kept.exists());
        assert!(!orphan.exists());
        assert!(stray.exists());

        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn is_running_finds_our_own_process() {
        // Our own comm is the test binary's name, truncated to 15 bytes.
        let exe = std::env::current_exe().unwrap();
        let name = exe.file_name().unwrap().to_string_lossy().to_string();
        let truncated = &name[..name.len().min(15)];
        assert!(is_running(truncated));
        assert!(!is_running("definitely-not-a-real-process"));
    }

    #[test]
    fn find_images_is_recursive_sorted_and_excludes_thumbnails() {
        let base = std::env::temp_dir().join(format!("lumen_test_{}", std::process::id()));
        let sub = base.join("nested");
        let thumb_dir = base.join(".thumbnails");
        fs::create_dir_all(&sub).unwrap();
        fs::create_dir_all(&thumb_dir).unwrap();

        fs::write(base.join("b.png"), b"x").unwrap();
        fs::write(base.join("a.jpg"), b"x").unwrap();
        fs::write(sub.join("c.webp"), b"x").unwrap();
        fs::write(base.join("ignored.txt"), b"x").unwrap();
        fs::write(thumb_dir.join("a.png"), b"x").unwrap();

        let mut found = find_images(&base, &thumb_dir);
        found.sort();

        let expected = {
            let mut v = vec![base.join("a.jpg"), base.join("b.png"), sub.join("c.webp")];
            v.sort();
            v
        };
        assert_eq!(found, expected);

        fs::remove_dir_all(&base).unwrap();
    }
}
