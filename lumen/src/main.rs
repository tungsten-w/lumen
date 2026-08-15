use chrono::{Datelike, Local, Timelike};
use rand::seq::SliceRandom;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::{Duration, SystemTime};

/// Largest edge of a generated thumbnail, in pixels.
///
/// wallpaper.rasi draws `element-icon` at 340px logical; the display runs at
/// scale 1.33, so 453 physical pixels is all rofi can ever show. Generating at
/// 900 like the original made rofi decode ~3x the pixels it needed.
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

fn parallelism() -> usize {
    thread::available_parallelism().map(|n| n.get()).unwrap_or(4)
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
            let is_dir = if ft.is_symlink() { path.is_dir() } else { ft.is_dir() };
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
/// they get regenerated instead of slowing rofi down forever.
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
                    let Some((img, thumb)) = todo.get(index) else { break };
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
/// refresh all happen here.
fn wallpaper_entries(dir: &Path) -> Vec<(PathBuf, PathBuf)> {
    let thumb_dir = dir.join(".thumbnails");
    if fs::create_dir_all(&thumb_dir).is_err() {
        eprintln!("Erreur : impossible de créer {}.", thumb_dir.display());
        std::process::exit(1);
    }

    let mut images = find_images(dir, &thumb_dir);
    if images.is_empty() {
        eprintln!("Erreur : Aucune image dans {}.", dir.display());
        std::process::exit(1);
    }
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

/// apply a (dark/light) wallpaper with rofi picker
fn pick_with_rofi(dir: &Path) -> Option<PathBuf> {
    let entries = wallpaper_entries(dir);

    // rofi selection
    let mut input = String::with_capacity(entries.len() * 128);
    for (img, thumb) in &entries {
        let Some(file_name) = img.file_name() else { continue };
        input.push_str(&file_name.to_string_lossy());
        input.push_str("\0icon\x1f");
        input.push_str(&thumb.to_string_lossy());
        input.push('\n');
    }

    let mut child = Command::new("rofi")
        .args([
            "-dmenu",
            "-p",
            "~ Select a wallpaper ~  ⏾ ",
            "-show-icons",
            "-icon-theme",
            "Papirus",
            "-theme",
        ])
        .arg(home_dir().join(".config/rofi/wallpaper.rasi"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .ok()?;

    child.stdin.take()?.write_all(input.as_bytes()).ok()?;
    let output = child.wait_with_output().ok()?;
    let selected = String::from_utf8_lossy(&output.stdout).trim().to_string();

    if selected.is_empty() {
        std::process::exit(0);
    }
    Some(dir.join(selected))
}

/// apply a (dark/light) wallpaper with the Quickshell picker
fn pick_with_quickshell(config: &Path, dir: &Path) -> Option<PathBuf> {
    let entries = wallpaper_entries(dir);

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
    let list = serde_json::json!({ "items": items }).to_string();

    let selected = run_quickshell(config, "picker", Some(&list))?;
    if selected.is_empty() {
        std::process::exit(0);
    }
    // Unlike rofi, which can only echo the line it was given, the Quickshell
    // picker answers with the full path — so wallpapers in sub-directories work.
    Some(PathBuf::from(selected))
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

/// apply all (awww, pywal, hyprpanel, obsidian...)
fn apply_all(wallpaper: &Path, dark: bool) {
    let wal_flags: Vec<&str> = if dark { vec!["-q"] } else { vec!["-l", "-q"] };
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

    // Pywal
    {
        let wallpaper = wallpaper.to_path_buf();
        let wal_flags: Vec<String> = wal_flags.into_iter().map(String::from).collect();
        handles.push(thread::spawn(move || {
            thread::sleep(TRANSITION_GUARD); // stay off the CPU while awww animates
            let status = Command::new("wal").arg("-i").arg(&wallpaper).args(&wal_flags).status();
            if !status.map(|s| s.success()).unwrap_or(false) {
                eprintln!("Erreur pywal.");
            }
        }));
    }

    // Copy /tmp (thumbnails for hyprpanel/rofi/hyprlock...)
    {
        let wallpaper = wallpaper.to_path_buf();
        handles.push(thread::spawn(move || {
            let _ = fs::copy(&wallpaper, "/tmp/current_wallpaper.png");
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
        handles.push(thread::spawn(move || {
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

            if is_running("spotify") {
                thread::sleep(Duration::from_secs(2));
                let _ = Command::new("spicetify").arg("restart").status();
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
            let vault_appear = home_dir().join("Documents/Obsidian Vault/.obsidian/appearance.json");
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
// MAIN MENU (QUICKSHELL / ROFI)
// ══════════════════════════════════════════════════════════════

const ICON_DARK: char = '\u{f4ee}';
const ICON_LIGHT: char = '\u{f522}';
const ICON_HEURE: char = '\u{f1803}';
const ICON_SAISON: char = '\u{f1a79}';

#[derive(Clone, Copy, PartialEq, Debug)]
enum Mode {
    Dark,
    Light,
    Heure,
    Saison,
}

impl Mode {
    /// rofi can only echo back the line it was handed, so it answers with the
    /// glyph; the Quickshell menu answers with a name, which is what makes its
    /// QML readable. Both spellings are accepted here.
    fn parse(answer: &str) -> Option<Mode> {
        match answer {
            "dark" => Some(Mode::Dark),
            "light" => Some(Mode::Light),
            "time" => Some(Mode::Heure),
            "season" => Some(Mode::Saison),
            _ => match answer.chars().next() {
                Some(ICON_DARK) => Some(Mode::Dark),
                Some(ICON_LIGHT) => Some(Mode::Light),
                Some(ICON_HEURE) => Some(Mode::Heure),
                Some(ICON_SAISON) => Some(Mode::Saison),
                _ => None,
            },
        }
    }
}

/// Which of the two front-ends draws the prompts.
enum Frontend {
    /// The Quickshell config to run, i.e. the `shell.qml` of `quickshell/lumen`.
    Quickshell(PathBuf),
    Rofi,
}

impl Frontend {
    /// Quickshell as soon as `qs` and the config are both installed, rofi
    /// otherwise. `LUMEN_FRONTEND=rofi` pins the old front-end, which is also
    /// what happens automatically if `qs` ever fails to start.
    fn detect() -> Frontend {
        if std::env::var("LUMEN_FRONTEND").as_deref() == Ok("rofi") {
            return Frontend::Rofi;
        }

        let candidates = [
            std::env::var_os("LUMEN_QS_CONFIG").map(PathBuf::from),
            Some(home_dir().join(".config/quickshell/lumen/shell.qml")),
            // Running straight from a clone of the dotfiles repository.
            Some(home_dir().join(".config/lumen/quickshell/lumen/shell.qml")),
        ];

        match candidates.into_iter().flatten().find(|path| path.is_file()) {
            Some(config) if has_command("qs") => Frontend::Quickshell(config),
            _ => Frontend::Rofi,
        }
    }
}

fn has_command(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| {
        std::env::split_paths(&path).any(|dir| dir.join(name).is_file())
    })
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

/// Shows one Quickshell prompt and waits for it, the way rofi was waited for.
///
/// `Some("")` is a cancelled prompt — Escape, or a click outside the window.
/// `None` means `qs` itself never got as far as answering, and the caller should
/// fall back to rofi rather than leave the user without a picker.
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
    if let Some(path) = &items_file {
        command.env("LUMEN_ITEMS", path);
    }
    let status = command.status();

    let answer = fs::read_to_string(&result).unwrap_or_default().trim().to_string();
    let _ = fs::remove_file(&result);
    if let Some(path) = items_file {
        let _ = fs::remove_file(path);
    }

    if !status.map(|s| s.success()).unwrap_or(false) {
        return None;
    }
    Some(answer)
}

/// Shows the mode menu and waits for one of the four entries.
fn choose_mode(frontend: &Frontend) -> Option<Mode> {
    if let Frontend::Quickshell(config) = frontend {
        if let Some(answer) = run_quickshell(config, "menu", None) {
            return Mode::parse(&answer);
        }
        eprintln!("Quickshell n'a pas répondu, retour à rofi.");
    }

    let menu = format!("{ICON_DARK}\n{ICON_LIGHT}\n{ICON_HEURE}\n{ICON_SAISON}");

    let mut child = Command::new("rofi")
        .args(["-dmenu", "-theme"])
        .arg(home_dir().join(".config/rofi/wallpaperchoise.rasi"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("échec du lancement de rofi");

    child
        .stdin
        .take()
        .expect("stdin manquant")
        .write_all(menu.as_bytes())
        .expect("échec de l'écriture dans rofi");
    let output = child.wait_with_output().expect("échec de l'exécution de rofi");

    Mode::parse(String::from_utf8_lossy(&output.stdout).trim())
}

/// Shows the thumbnail grid for `dir` and waits for a wallpaper.
fn pick_wallpaper(frontend: &Frontend, dir: &Path) -> Option<PathBuf> {
    if let Frontend::Quickshell(config) = frontend {
        if let Some(wallpaper) = pick_with_quickshell(config, dir) {
            return Some(wallpaper);
        }
        eprintln!("Quickshell n'a pas répondu, retour à rofi.");
    }
    pick_with_rofi(dir)
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

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
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

    let frontend = Frontend::detect();

    match choose_mode(&frontend) {
        // Dark — thumbnail picker
        Some(Mode::Dark) => {
            if let Some(wp) = pick_wallpaper(&frontend, &home_dir().join("Pictures/Wallpapers/dark")) {
                apply_all(&wp, true);
            }
        }
        // Light — thumbnail picker
        Some(Mode::Light) => {
            if let Some(wp) = pick_wallpaper(&frontend, &home_dir().join("Pictures/Wallpapers/light")) {
                apply_all(&wp, false);
            }
        }
        // Heure — random, dark if night/sunset
        Some(Mode::Heure) => {
            let moment = get_moment_journee();
            if let Some(wp) = pick_random(&home_dir().join(format!("Pictures/Wallpapers/season-time/{moment}"))) {
                let dark = moment == "night" || moment == "sunset";
                apply_all(&wp, dark);
            }
        }
        // Saison — random, light
        Some(Mode::Saison) => {
            let saison = get_saison();
            if let Some(wp) = pick_random(&home_dir().join(format!("Pictures/Wallpapers/season-time/{saison}"))) {
                apply_all(&wp, false);
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
    fn mode_parses_both_frontends() {
        // What the Quickshell menu writes.
        assert_eq!(Mode::parse("dark"), Some(Mode::Dark));
        assert_eq!(Mode::parse("light"), Some(Mode::Light));
        assert_eq!(Mode::parse("time"), Some(Mode::Heure));
        assert_eq!(Mode::parse("season"), Some(Mode::Saison));

        // What rofi echoes back.
        assert_eq!(Mode::parse(&ICON_DARK.to_string()), Some(Mode::Dark));
        assert_eq!(Mode::parse(&ICON_LIGHT.to_string()), Some(Mode::Light));
        assert_eq!(Mode::parse(&ICON_HEURE.to_string()), Some(Mode::Heure));
        assert_eq!(Mode::parse(&ICON_SAISON.to_string()), Some(Mode::Saison));

        // A cancelled prompt is empty in both cases.
        assert_eq!(Mode::parse(""), None);
        assert_eq!(Mode::parse("whatever"), None);
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
