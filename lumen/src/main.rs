use chrono::{Datelike, Local, Timelike};
use rand::seq::SliceRandom;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
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

/// `~/Pictures/Wallpapers`, where every built-in mode keeps its images.
fn wallpapers() -> PathBuf {
    home_dir().join("Pictures/Wallpapers")
}

/// The link `apply_all` keeps pointed at the wallpaper that is up.
fn current_link() -> PathBuf {
    wallpapers().join("current_wallpaper.jpg")
}

/// `~/.config/lumen/settings.json` — `None` when it is missing or unreadable.
fn settings() -> Option<serde_json::Value> {
    let raw = fs::read_to_string(home_dir().join(".config/lumen/settings.json")).ok()?;
    serde_json::from_str(&raw).ok()
}

/// XDG_RUNTIME_DIR: a user-owned tmpfs, so nothing put there reaches the disk.
fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
}

/// Runs a tool to its end, and says so when it fails rather than swallowing it.
fn run(command: &mut Command) -> bool {
    let ok = command.status().is_ok_and(|status| status.success());
    if !ok {
        eprintln!("lumen : échec de {command:?}");
    }
    ok
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
    // `exists()` follows the link, so one left pointing at a wallpaper that has
    // since been deleted is skipped rather than copied as an error.
    let kept = current_link();
    if !kept.exists() {
        return;
    }
    if !Path::new(CURRENT_WALLPAPER).exists() {
        cache_wallpaper_still(&kept);
    }
    // A GIF is played by mpvpaper, which nothing restarts at login: awww comes
    // back with the transparent image it was left on, and nothing under it.
    // The link is always called `.jpg`: what it points at says what it is.
    if let Ok(real) = fs::canonicalize(&kept)
        && is_gif(&real)
        && processes_where(is_mpvpaper_cmdline).is_empty()
        && Command::new("awww")
            .arg("query")
            .output()
            .is_ok_and(|out| String::from_utf8_lossy(&out.stdout).contains("lumen/clear.png"))
    {
        play_gif(&real);
    }
}

/// Converts the first frame of `from` into a PNG at `to`, and says whether it
/// did. `options` holds the whole command line, `-[0]` standing for the image.
///
/// The image goes in on stdin and comes out on stdout because ImageMagick reads
/// file *names* as instructions: a `%d` in one is a frame counter, a `[` a
/// frame selector — a wallpaper called `100% done.png` never got a thumbnail.
/// Written beside its final name, so a run that is killed half way never
/// leaves a broken file that looks up to date.
fn magick_png(from: &Path, options: &[&str], to: &Path) -> bool {
    let part = PathBuf::from(format!("{}.part", to.display()));
    let made = fs::File::open(from)
        .and_then(|image| Ok((image, fs::File::create(&part)?)))
        .is_ok_and(|(image, png)| {
            run(Command::new("magick")
                .arg("-quiet") // warnings only: a PNG with broken XMP converts fine
                .args(options)
                .arg("png:-")
                .stdin(image)
                .stdout(png))
        })
        && fs::rename(&part, to).is_ok();
    if !made {
        let _ = fs::remove_file(&part);
    }
    made
}

fn is_gif(path: &Path) -> bool {
    path.extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("gif"))
}

/// Largest edge of the still the menu draws behind itself. No window is wider
/// than the screen, and a wallpaper can be 10240 pixels across: converting that
/// at full size took 8 to 20 seconds per apply, and left the menu a 48 MB PNG
/// to decode on every launch.
const STILL_MAX_EDGE: u32 = 2560;

/// Keep the menu's still-image cache as a real PNG, whatever the wallpaper is —
/// a GIF gives its first frame. Shrunk to `STILL_MAX_EDGE` and barely
/// compressed: it lives in RAM and is read once, so encoding time is the only
/// cost that matters.
fn cache_wallpaper_still(wallpaper: &Path) {
    let size = format!("{STILL_MAX_EDGE}x{STILL_MAX_EDGE}");
    let options = [
        // Lets libjpeg decode a huge JPEG straight to a fraction of its size.
        "-define",
        &format!("jpeg:size={size}"),
        "-[0]",
        "-resize",
        &format!("{size}>"),
        "-define",
        "png:compression-level=1",
    ];
    if !magick_png(wallpaper, &options, Path::new(CURRENT_WALLPAPER)) {
        eprintln!("Could not cache wallpaper {}", wallpaper.display());
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
        .map(|e| matches!(e.to_lowercase().as_str(), "jpg" | "jpeg" | "png" | "gif" | "webp"))
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

/// The small, playing copy of a GIF the picker shows under the cursor — `None`
/// for anything that is not one. It sits beside the still thumbnail.
///
/// The picker used to play the wallpaper itself there: 2560 pixels wide and up
/// to 260 MB, decoded at full size only to be drawn in a 340 pixel box.
fn gif_preview(img: &Path, thumb: &Path) -> Option<PathBuf> {
    is_gif(img).then(|| thumb.with_extension("gif"))
}

/// True when `made` is missing or older than the `img` it was made from.
fn is_outdated(made: &Path, img: &Path) -> bool {
    let mtime = |path: &Path| path.metadata().and_then(|meta| meta.modified()).ok();
    mtime(made) < mtime(img)
}

/// Regenerates every stale thumbnail and GIF preview, one process per core.
///
/// `MAGICK_THREAD_LIMIT=1` matters as much as the fan-out here: left alone each
/// magick spins up its own OpenMP pool, and the resulting oversubscription costs
/// more than it buys once we are already running one process per core.
fn generate_thumbnails(pairs: &[(PathBuf, PathBuf)]) {
    let mut todo: Vec<(&Path, PathBuf)> = Vec::new();
    for (img, thumb) in pairs {
        if thumb_is_stale(thumb, img) {
            todo.push((img, thumb.clone()));
        }
        if let Some(preview) = gif_preview(img, thumb).filter(|p| is_outdated(p, img)) {
            todo.push((img, preview));
        }
    }

    let next = AtomicUsize::new(0);
    thread::scope(|scope| {
        for _ in 0..parallelism().min(todo.len()) {
            scope.spawn(|| {
                while let Some((img, out)) = todo.get(next.fetch_add(1, Ordering::Relaxed)) {
                    if out.extension().is_none_or(|e| e != "gif") {
                        let size = format!("{THUMB_MAX_EDGE}x{THUMB_MAX_EDGE}>");
                        magick_png(img, &["-[0]", "-thumbnail", &size, "-strip"], out);
                        continue;
                    }
                    let part = format!("{}.part", out.display());
                    let scale =
                        format!("fps=12,scale='min({THUMB_MAX_EDGE},iw)':-2:flags=fast_bilinear");
                    let made = Command::new("ffmpeg")
                        .args(["-v", "quiet", "-y", "-i"])
                        .arg(img)
                        .args(["-vf", &scale, "-f", "gif", &part])
                        .stdin(Stdio::null())
                        .status()
                        .is_ok_and(|status| status.success());
                    if !made || fs::rename(&part, out).is_err() {
                        let _ = fs::remove_file(&part);
                    }
                }
            });
        }
    });
}

/// Every wallpaper of `dir`, sorted and paired with where its thumbnail lives.
/// `None` when the thumbnail directory cannot be made.
fn thumb_pairs(dir: &Path) -> Option<Vec<(PathBuf, PathBuf)>> {
    let thumb_dir = dir.join(".thumbnails");
    fs::create_dir_all(&thumb_dir).ok()?;
    let mut images = find_images(dir, &thumb_dir);
    images.sort();
    // `a.jpg`, `a.gif` and `sub/a.jpg` would all land on `a.png`: the first keeps
    // the short name, the others take their full name, then their path.
    let mut taken = std::collections::HashSet::new();
    let pairs = images.into_iter().filter_map(|img| {
        let relative = img.strip_prefix(dir).ok()?.to_string_lossy().replace('/', "_");
        let names = [
            img.file_stem()?.to_string_lossy().into_owned(),
            img.file_name()?.to_string_lossy().into_owned(),
            relative,
        ];
        let name = names.into_iter().find(|name| taken.insert(name.clone()))?;
        Some((img, thumb_dir.join(format!("{name}.png"))))
    });
    Some(pairs.collect())
}

/// Every wallpaper of `dir`, paired with its thumbnail and ready to display.
///
/// Both front-ends need the same list, so the scan, the sort and the thumbnail
/// refresh all happen here. An empty directory gives an empty list: the pickers
/// treat that as an error, but `--settings` is happy to show an empty grid.
fn wallpaper_entries(dir: &Path) -> Vec<(PathBuf, PathBuf)> {
    let Some(pairs) = thumb_pairs(dir) else {
        eprintln!("Erreur : impossible de créer les vignettes de {}.", dir.display());
        return Vec::new();
    };
    generate_thumbnails(&pairs);
    pairs
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
                // Absent when ffmpeg is: the picker then plays the GIF itself.
                "preview": gif_preview(img, thumb)
                    .filter(|preview| preview.is_file())
                    .map(|preview| preview.to_string_lossy().into_owned()),
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
    images.choose(&mut rand::thread_rng()).cloned()
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

/// The arguments of a `/proc/<pid>/cmdline`. NUL-separated as a rule — but
/// Spotify, like every Chromium, rewrites its own with spaces, and read as one
/// argument its main process was never recognised: every apply then took the
/// watcher for a stale one, waited up to 15 s and restarted it.
fn argv(cmdline: &[u8]) -> impl Iterator<Item = &[u8]> {
    cmdline
        .split(|&b| b == 0 || b == b' ')
        .filter(|arg| !arg.is_empty())
}

/// Whether a `/proc/<pid>/cmdline` is a `spicetify watch`.
///
/// The arguments arrive NUL-separated. `comm` alone cannot tell a watch from
/// an `apply` or a `refresh` that happens to be running, so this reads the
/// command line instead — `pgrep -f`, without the fork.
fn is_watch_cmdline(cmdline: &[u8]) -> bool {
    let mut args = argv(cmdline);
    let is_spicetify = args
        .next()
        .is_some_and(|argv0| argv0.rsplit(|&b| b == b'/').next() == Some(b"spicetify"));
    is_spicetify && args.any(|arg| arg == b"watch")
}

/// Whether a `/proc/<pid>/cmdline` is Spotify's main process.
///
/// Every helper Spotify forks — zygote, renderer, crashpad — is also called
/// `spotify`, and only they carry a `--type=`.
fn is_spotify_main_cmdline(cmdline: &[u8]) -> bool {
    let mut args = argv(cmdline);
    let is_spotify = args
        .next()
        .is_some_and(|argv0| argv0.rsplit(|&b| b == b'/').next() == Some(b"spotify"));
    is_spotify && !args.any(|arg| arg.starts_with(b"--type="))
}

/// When a process started, in clock ticks since boot, out of its
/// `/proc/<pid>/stat` — field 22. The name in field 2 sits in parentheses and
/// may itself hold spaces or a `)`, so the count starts after the last one.
fn start_time_of(stat: &str) -> Option<u64> {
    stat.rsplit_once(')')?
        .1
        .split_whitespace()
        .nth(19)?
        .parse()
        .ok()
}

/// Every process whose command line `matches`, with when it started.
fn processes_where(matches: fn(&[u8]) -> bool) -> Vec<(String, u64)> {
    let Ok(entries) = fs::read_dir("/proc") else {
        return Vec::new();
    };
    entries
        .flatten()
        .filter_map(|entry| {
            let pid = entry.file_name().to_string_lossy().to_string();
            if !pid.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            let cmdline = fs::read(entry.path().join("cmdline")).ok()?;
            if !matches(&cmdline) {
                return None;
            }
            let stat = fs::read_to_string(entry.path().join("stat")).ok()?;
            Some((pid, start_time_of(&stat)?))
        })
        .collect()
}

/// Whether a `spicetify watch` is running against the Spotify open right now.
///
/// A watcher keeps the DevTools address of the Spotify it started with. Close
/// Spotify and open it again and that address is dead: the watcher still runs,
/// but the next change it sees fails to reload and kills it — taking that
/// wallpaper's colours with it. So a watcher older than Spotify does not count.
fn spicetify_is_watching() -> bool {
    let Some(spotify) = processes_where(is_spotify_main_cmdline)
        .into_iter()
        .map(|(_, started)| started)
        .max()
    else {
        return false;
    };
    processes_where(is_watch_cmdline)
        .iter()
        .any(|&(_, started)| started >= spotify)
}

/// The port `spicetify watch` reaches Spotify on, and the flags that open it.
///
/// They are also in `~/.config/spotify-flags.conf`, which Arch's `spotify`
/// wrapper reads on every launch — that is what keeps a restart from ever being
/// needed. The origin is `spicetify`'s own, not `*`: any page in a browser could
/// otherwise talk to Spotify through it.
const SPOTIFY_DEVTOOLS: &str = "127.0.0.1:9222";
const SPOTIFY_DEVTOOLS_FLAGS: [&str; 2] = [
    "--remote-debugging-port=9222",
    "--remote-allow-origins=http://localhost/",
];

/// Whether Spotify answers on its DevTools port.
fn spotify_devtools_open() -> bool {
    use std::io::Write;
    use std::net::TcpStream;

    let Ok(address) = SPOTIFY_DEVTOOLS.parse() else {
        return false;
    };
    let Ok(mut stream) = TcpStream::connect_timeout(&address, Duration::from_millis(500)) else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
    if stream
        .write_all(b"GET /json/list HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        .is_err()
    {
        return false;
    }
    // A timeout still leaves whatever did arrive in the buffer.
    let mut answer = Vec::new();
    let _ = stream.read_to_end(&mut answer);
    answer.windows(7).any(|window| window == b"spotify")
}

/// Restarts Spotify with its DevTools port open, and says whether it came up.
///
/// `spicetify watch` would do this itself, but it starts the new Spotify the
/// instant the old one has been sent SIGTERM. The new one finds the old one
/// still there, hands over to it and exits, then the old one exits as well: no
/// Spotify at all, and a watcher polling for a port that never opens, at 100%
/// CPU, forever. So the old one is waited out first.
fn restart_spotify_with_devtools() -> bool {
    let _ = Command::new("pkill").args(["-x", "spotify"]).status();
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    while is_running("spotify") {
        if std::time::Instant::now() > deadline {
            return false;
        }
        thread::sleep(Duration::from_millis(200));
    }

    if Command::new("nohup")
        .arg("spotify")
        .args(SPOTIFY_DEVTOOLS_FLAGS)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .is_err()
    {
        return false;
    }

    let deadline = std::time::Instant::now() + Duration::from_secs(20);
    while std::time::Instant::now() < deadline {
        if spotify_devtools_open() {
            return true;
        }
        thread::sleep(Duration::from_millis(200));
    }
    false
}

/// Starts `spicetify watch -s`, detached, unless one is already watching.
///
/// Official spicetify has no one-shot live reload — `refresh` restarts Spotify,
/// `refresh -n` rewrites the CSS without reloading anything. `watch -s` is the
/// way it does it: a long-lived process that rereads the active theme's
/// `color.ini` every 200 ms and reloads Spotify through DevTools whenever it
/// changes. Once it runs, the colours follow Noctalia's rewrite on their own
/// and there is nothing left for `lumen` to do.
///
/// On its first pass it treats every file as changed, so starting it pushes
/// the palette already on disk — which is why the caller waits for Noctalia's
/// write first.
///
/// It is never left to open DevTools by itself: see
/// `restart_spotify_with_devtools` for what it does then. With the flags in
/// `spotify-flags.conf` the port is already open and nothing restarts at all.
fn ensure_spicetify_watch() {
    if spicetify_is_watching() {
        return;
    }

    // What is left belongs to a Spotify that has since been closed, or is
    // stuck waiting for a port that never opened.
    for (pid, _) in processes_where(is_watch_cmdline) {
        let _ = Command::new("kill").arg(&pid).status();
    }

    if !spotify_devtools_open() && !restart_spotify_with_devtools() {
        eprintln!("Spotify n'a pas ouvert DevTools; ses couleurs suivront au prochain fond.");
        return;
    }

    // Kept rather than thrown away: a watcher that dies in the background has
    // nobody to tell, and this is the only place it can say why.
    let log_dir = home_dir().join(".cache/lumen");
    let _ = fs::create_dir_all(&log_dir);
    let log = fs::File::create(log_dir.join("spicetify-watch.log"))
        .ok()
        .and_then(|file| Some((file.try_clone().ok()?, file)));
    let (stdout, stderr) = match log {
        Some((copy, file)) => (Stdio::from(file), Stdio::from(copy)),
        None => (Stdio::null(), Stdio::null()),
    };

    if Command::new("nohup")
        .args(["spicetify", "watch", "-s"])
        .stdin(Stdio::null())
        .stdout(stdout)
        .stderr(stderr)
        .spawn()
        .is_err()
    {
        eprintln!("spicetify introuvable.");
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

/// Whether a `/proc/<pid>/cmdline` is an mpvpaper.
fn is_mpvpaper_cmdline(cmdline: &[u8]) -> bool {
    let argv0 = argv(cmdline).next().unwrap_or_default();
    argv0.rsplit(|&b| b == b'/').next() == Some(b"mpvpaper")
}

/// Starts mpvpaper on `gif`, under awww, and says whether it started.
fn play_gif(gif: &Path) -> bool {
    Command::new("nohup")
        .args(["mpvpaper", "-l", "background", "-o"])
        // `panscan` fills the screen by cropping, the way awww does.
        .args(["loop no-audio panscan=1.0 really-quiet", "*"])
        .arg(gif)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .is_ok()
}

/// The frame rate to animate a transition at: the fastest monitor's refresh
/// rate. At a fixed 60 a transition visibly stutters on a 165 Hz screen, and
/// awww keeps up easily — half a core for both monitors at 180.
fn transition_fps() -> String {
    Command::new("hyprctl")
        .args(["-j", "monitors"])
        .output()
        .ok()
        .and_then(|out| serde_json::from_slice::<serde_json::Value>(&out.stdout).ok())
        .and_then(|monitors| {
            let rates = monitors.as_array()?.iter();
            rates
                .filter_map(|monitor| monitor.get("refreshRate")?.as_f64())
                .reduce(f64::max)
        })
        .map_or(60, |hz| hz.round() as u32)
        .to_string()
}

/// Puts the wallpaper on screen: awww for a still, mpvpaper for a GIF.
///
/// awww can animate a GIF, but only after resizing and compressing every frame
/// for every monitor — measured at 10 to 41 seconds the first time, and over a
/// gigabyte of cache for one file. mpv just plays it, nothing cached.
///
/// So a GIF arrives the way a still does — awww transitions to its first frame
/// — while mpvpaper starts on the `background` layer, under awww. Once the
/// transition is over awww is handed a transparent image and the player shows
/// through, with whatever else lives on the `bottom` layer (desktop widgets)
/// still on top. Without mpvpaper installed, awww animates the GIF itself.
///
/// `transition_started` is raised when awww has taken the image: its client
/// spends half a second decoding first, so that — not the launch — is when
/// the animation begins.
fn show_wallpaper(wallpaper: &Path, transition_started: &AtomicBool) {
    let fps = transition_fps();
    let awww = |image: &Path, kind: &str| {
        run(Command::new("awww").arg("img").arg(image).args([
            "--transition-type",
            kind,
            "--transition-fps",
            &fps,
            "--transition-duration",
            "0.7",
        ]))
    };
    // The previous GIF's player. It goes once the new wallpaper covers it.
    let old = processes_where(is_mpvpaper_cmdline);
    let cache = home_dir().join(".cache/lumen");
    let (frame, clear) = (cache.join("gif-frame.png"), cache.join("clear.png"));
    let fast = ["-[0]", "-define", "png:compression-level=1"];
    let live = is_gif(wallpaper)
        && has_command("mpvpaper")
        && fs::create_dir_all(&cache).is_ok()
        && magick_png(wallpaper, &fast, &frame)
        && (clear.is_file()
            || run(Command::new("magick")
                .args(["-size", "16x16", "xc:none"])
                .arg(&clear)));

    awww(if live { &frame } else { wallpaper }, "random");
    transition_started.store(true, Ordering::Relaxed);

    let playing = live && play_gif(wallpaper);
    if playing || !old.is_empty() {
        // The transition, then the moment mpv needs to draw its first frame.
        thread::sleep(TRANSITION_GUARD + Duration::from_millis(300));
    }
    for (pid, _) in old {
        let _ = Command::new("kill").arg(pid).status();
    }
    if playing {
        awww(&clear, "none");
    }
}

/// Apply wallpaper and themes. Every step is independent of the others, so each
/// gets a thread and the whole thing takes as long as the slowest one.
fn apply_all(wallpaper: &Path, dark: bool) {
    // Everything the theming tools write from here on is newer than this.
    let started = SystemTime::now();
    let mode = if dark { "dark" } else { "light" };
    let (run_pywal, run_wallust) = classic_generators(settings().as_ref());

    // Nothing heavy runs while awww animates: a palette tool, a GTK reload or
    // Noctalia repainting its bar in the middle of the transition is what makes
    // it stutter. They all hold off until it has started, then for as long as
    // it lasts.
    let transition_started = AtomicBool::new(false);
    let after_transition = || {
        while !transition_started.load(Ordering::Relaxed) {
            thread::sleep(Duration::from_millis(20));
        }
        thread::sleep(TRANSITION_GUARD);
    };

    thread::scope(|scope| {
        scope.spawn(|| show_wallpaper(wallpaper, &transition_started));

        // The quick ones: a few milliseconds each, so they share a thread.
        scope.spawn(|| {
            // `-x` rather than `-f`: matching the whole command line would also
            // kill anything that merely mentions feh, this script's own
            // launcher included.
            let _ = Command::new("pkill").args(["-x", "feh"]).status();
            let _ = Command::new("pkill").args(["-f", "ulauncher"]).status();
            let cursor = if dark {
                "Bibata-Modern-Classic"
            } else {
                "Bibata-Modern-Ice"
            };
            let _ = Command::new("hyprctl")
                .args(["setcursor", cursor, "24"])
                .status();

            // Renamed into place, so the link never goes missing in between.
            let link = current_link();
            let fresh = link.with_extension("new");
            let _ = fs::remove_file(&fresh);
            if std::os::unix::fs::symlink(wallpaper, &fresh)
                .and_then(|()| fs::rename(&fresh, &link))
                .is_err()
            {
                eprintln!("Erreur : impossible de mettre à jour {}.", link.display());
            }
        });

        // The still the menu draws behind itself, in /tmp.
        scope.spawn(|| {
            after_transition();
            cache_wallpaper_still(wallpaper);
        });

        // Classic palette provider(s). Both run only when the menu and picker
        // use different classic sources.
        scope.spawn(|| {
            after_transition();
            if run_pywal {
                // `-n`: pywal would otherwise set the wallpaper a second time
                // itself, through a plain `awww img` — over the GIF player too.
                let flags: &[&str] = if dark { &["-nq"] } else { &["-lnq"] };
                run(Command::new("wal").arg("-i").arg(wallpaper).args(flags));
            }
            if run_wallust
                && run(Command::new("wallust")
                    .arg("run")
                    .arg(wallpaper)
                    .args(["--palette", mode]))
            {
                if let Some(hook) = std::env::var_os("LUMEN_WALLUST_HOOK") {
                    run(Command::new(hook)
                        .env("LUMEN_DARK_MODE", mode)
                        .env("LUMEN_WALLPAPER", wallpaper));
                }
                let cache = home_dir().join(".cache/wallust");
                if !cache.join("colors-rofi-dark.rasi").is_file()
                    || !cache.join("colors.json").is_file()
                {
                    eprintln!(
                        "Wallust: configurez les templates Lumen dans ~/.config/wallust/wallust.toml."
                    );
                }
            }
            reload_brave(run_wallust);
        });

        // Matugen (gtk/rofi/tmux/neovim theming)
        scope.spawn(|| {
            after_transition();
            run(Command::new("matugen")
                .arg("image")
                .arg(wallpaper)
                .args(["--mode", mode, "-c"])
                .arg(home_dir().join(".config/matugen/config.toml"))
                .args(["--prefer", "saturation", "-q"]));
        });

        // Noctalia + Spicetify
        scope.spawn(|| {
            after_transition();
            if std::env::var("LUMEN_SKIP_NOCTALIA").as_deref() != Ok("1") {
                if !is_running("noctalia") {
                    let _ = Command::new("nohup")
                        .args(["noctalia", "-d"])
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn();
                    thread::sleep(Duration::from_secs(3));
                }
                run(Command::new("noctalia").args(["msg", "theme-mode-set", mode]));
                run(Command::new("noctalia")
                    .args(["msg", "wallpaper-set"])
                    .arg(wallpaper));
            }

            // A watcher already running sees Noctalia's rewrite of `color.ini`
            // by itself and reloads Spotify; there is nothing to wait for.
            if is_running("spotify") && !spicetify_is_watching() {
                // Spotify's colours are not ours to write: Noctalia's own
                // spicetify template writes them, and it does so a good while
                // after `wallpaper-set` has returned — measured at three seconds.
                // A watcher started before that would push the *previous*
                // wallpaper's palette on its first pass, then reload a second
                // time once the file changed.
                //
                // So we wait for the file itself rather than for a duration.
                match spicetify_colors() {
                    Some(colors) => {
                        wait_for_write(&colors, started, Duration::from_secs(15));
                    }
                    None => thread::sleep(Duration::from_secs(3)),
                }
                ensure_spicetify_watch();
            }
        });

        // Obsidian: Obsidian dark, Moonstone light.
        scope.spawn(|| {
            let vault = home_dir().join("Documents/Obsidian Vault/.obsidian");
            update_json_field(&vault.join("app.json"), "baseTheme", mode);
            let theme = if dark { "obsidian" } else { "moonstone" };
            update_json_field(&vault.join("appearance.json"), "theme", theme);

            if dark {
                let launch = |program: &str, args: &[&str]| {
                    Command::new("nohup")
                        .arg(program)
                        .args(args)
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn()
                };
                if launch("flatpak", &["run", "md.obsidian.Obsidian"]).is_err() {
                    let _ = launch("obsidian", &[]);
                }
            }
        });
    });
}

// ══════════════════════════════════════════════════════════════
// MAIN MENU
// ══════════════════════════════════════════════════════════════

/// Dark or light for the season's wallpaper — the one mode whose folder does
/// not decide it.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Shade {
    Dark,
    Light,
    /// Follows the clock the way Time does: dark once the sun is down.
    Auto,
}

impl Shade {
    fn parse(word: &str) -> Option<Shade> {
        match word {
            "dark" => Some(Shade::Dark),
            "light" => Some(Shade::Light),
            "auto" => Some(Shade::Auto),
            _ => None,
        }
    }

    fn is_dark(self, hour: u32) -> bool {
        match self {
            Shade::Dark => true,
            Shade::Light => false,
            Shade::Auto => moment_for_hour(hour) != "day",
        }
    }
}

#[derive(Clone, PartialEq, Debug)]
enum Mode {
    Dark,
    Light,
    Heure,
    /// The menu answers `season:dark` or `season:light` once its question has
    /// been answered, or `season:auto` when the panel says to follow the clock.
    Saison(Shade),
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
        if let Some(shade) = answer.strip_prefix("season:") {
            return Shade::parse(shade).map(Mode::Saison);
        }
        match answer {
            "dark" => Some(Mode::Dark),
            "light" => Some(Mode::Light),
            "time" => Some(Mode::Heure),
            // A menu from before the question: light, as it always was.
            "season" => Some(Mode::Saison(Shade::Light)),
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
    runtime_dir().join(format!("lumen-{name}-{}", std::process::id()))
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
    if let Some(path) = current_wallpaper_path(&current_link()) {
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
    if let Some(wp) = pick_random(&wallpapers().join("season-time").join(moment)) {
        apply_all(&wp, moment == "night" || moment == "sunset");
    }
}

/// Random wallpaper for the season it is, in whichever mode was asked for.
///
/// A season says nothing about the hour, so the mode is not taken from the
/// folder the way Time takes it: the mode menu asks — see `Shade` — or the
/// settings panel has said once and for all.
fn apply_season(shade: Shade) {
    let saison = get_saison();
    if let Some(wp) = pick_random(&wallpapers().join("season-time").join(saison)) {
        apply_all(&wp, shade.is_dark(Local::now().hour()));
    }
}

/// What `modes.seasonTheme` says the season should be drawn in, for a run
/// that has nobody to ask.
///
/// `ask` is the mode menu's question, and a timer cannot answer one: it falls
/// back to light, which is what the season has always been.
fn season_shade_setting(settings: Option<&serde_json::Value>) -> Shade {
    settings
        .and_then(|value| value.get("modes"))
        .and_then(|value| value.get("seasonTheme"))
        .and_then(|value| value.as_str())
        .and_then(Shade::parse)
        .unwrap_or(Shade::Light)
}

/// Path of the lock the unattended modes hold.
fn auto_lock() -> PathBuf {
    runtime_dir().join("lumen-auto.lock")
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

    let list = items_json(&wallpaper_entries(&wallpapers().join("dark")));
    quickshell_or_die(config, "settings", Some(&list));
}

/// Deletes thumbnails whose source image is gone (renamed or removed), which
/// otherwise accumulate in the cache forever. Returns how many were freed.
fn prune_thumbnails(thumb_dir: &Path, keep: &[(PathBuf, PathBuf)]) -> (usize, u64) {
    let live: std::collections::HashSet<PathBuf> = keep
        .iter()
        .flat_map(|(img, thumb)| [Some(thumb.clone()), gif_preview(img, thumb)])
        .flatten()
        .collect();

    let Ok(entries) = fs::read_dir(thumb_dir) else {
        return (0, 0);
    };
    let (mut count, mut bytes) = (0, 0);
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "png" && e != "gif") || live.contains(&path) {
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
    let pairs = wallpaper_entries(dir);
    let (pruned, bytes) = prune_thumbnails(&dir.join(".thumbnails"), &pairs);
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
  lumen --season [MODE]  a random wallpaper for the season, no prompt —
                         MODE is dark, light or auto (dark after sunset);
                         without it, the menu's Season setting decides
  lumen --settings       the picker's settings: shape, motion, layout, color
  lumen --thumbs [DIR…]  rebuild the thumbnails without showing anything
  lumen --restore        after login: bring an animated wallpaper back to life
  lumen --help           this

The picker's settings also open from inside it, with Ctrl+, or by typing
`settings` into its search field. The mode menu keeps its own panel, on its cog
or on the same Ctrl+,.";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let flag = args.first().map(String::as_str);
    if matches!(flag, Some("--help" | "-h")) {
        println!("{USAGE}");
        return;
    }
    // Nothing below draws before this: /tmp does not survive a reboot, and the
    // menu is the first thing that wants the image back.
    restore_current_wallpaper();

    match flag {
        // Unattended: no prompt at all, for a timer or a keybind of its own.
        Some("--time" | "--season") => {
            let shade = match args.get(1) {
                _ if flag == Some("--time") => None,
                Some(word) => Some(Shade::parse(word).unwrap_or_else(|| {
                    eprintln!("Unknown season mode: {word} (dark, light or auto)\n\n{USAGE}");
                    std::process::exit(2);
                })),
                None => Some(season_shade_setting(settings().as_ref())),
            };
            take_auto_lock();
            match shade {
                Some(shade) => apply_season(shade),
                None => apply_time_of_day(),
            }
            let _ = fs::remove_file(auto_lock());
        }
        // `restore_current_wallpaper` above is all of it.
        Some("--restore") => {}
        Some("--settings") => open_settings(&quickshell_config()),
        Some("--thumbs") => {
            let dirs: Vec<PathBuf> = match &args[1..] {
                [] => vec![wallpapers().join("dark"), wallpapers().join("light")],
                given => given.iter().map(PathBuf::from).collect(),
            };
            dirs.iter().for_each(|dir| warm_thumbnails(dir));
        }
        // An unknown flag is a typo, not a wallpaper directory: say so rather
        // than opening the menu as if nothing had been asked for.
        Some(unknown) if unknown.starts_with('-') => {
            eprintln!("Unknown option: {unknown}\n\n{USAGE}");
            std::process::exit(2);
        }
        _ => menu(),
    }
}

/// `lumen` on its own: the mode menu, then whatever it answered.
fn menu() {
    let _ = Command::new("nohup")
        .arg(home_dir().join(".config/.scripts/wallpaper_recognition.sh"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();

    let config = quickshell_config();
    match choose_mode(&config) {
        // Dark or Light — the thumbnail picker on that folder.
        Some(mode @ (Mode::Dark | Mode::Light)) => {
            let dark = mode == Mode::Dark;
            let folder = wallpapers().join(if dark { "dark" } else { "light" });
            apply_all(&pick_with_quickshell(&config, &folder), dark);
        }
        // Heure — random, dark if night/sunset
        Some(Mode::Heure) => apply_time_of_day(),
        // Saison — random, in the mode the menu was told
        Some(Mode::Saison(shade)) => apply_season(shade),
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
    fn a_spicetify_watch_is_told_apart_from_other_runs() {
        // Exactly as /proc hands it over: NUL-separated, NUL-terminated.
        assert!(is_watch_cmdline(b"spicetify\0watch\0-s\0"));
        assert!(is_watch_cmdline(b"/usr/bin/spicetify\0watch\0-s\0"));
        assert!(is_watch_cmdline(b"spicetify\0-q\0watch\0-l\0"));

        // Spicetify doing something else, and something else mentioning watch.
        assert!(!is_watch_cmdline(b"spicetify\0apply\0"));
        assert!(!is_watch_cmdline(b"spicetify\0refresh\0-n\0"));
        assert!(!is_watch_cmdline(b"nvim\0spicetify\0watch\0"));
        assert!(!is_watch_cmdline(b"/usr/bin/notspicetify\0watch\0"));
        assert!(!is_watch_cmdline(b""));
    }

    #[test]
    fn spotify_main_is_told_apart_from_its_helpers() {
        assert!(is_spotify_main_cmdline(b"/opt/spotify/spotify\0--uri\0"));
        // What a running Spotify really shows: one string, spaces and all.
        assert!(is_spotify_main_cmdline(
            b"/opt/spotify/spotify --remote-debugging-port=9222 --remote-allow-origins=http://localhost/ --uri\0"
        ));
        assert!(!is_spotify_main_cmdline(
            b"/opt/spotify/spotify --type=renderer --lang=en-US\0"
        ));
        assert!(is_spotify_main_cmdline(
            b"/opt/spotify/spotify\0--remote-debugging-port=9222\0"
        ));

        assert!(!is_spotify_main_cmdline(
            b"/opt/spotify/spotify\0--type=zygote\0--no-sandbox\0"
        ));
        assert!(!is_spotify_main_cmdline(
            b"/opt/spotify/spotify\0--monitor-self-annotation=ptype=crashpad-handler\0--type=crashpad-handler\0"
        ));
        assert!(!is_spotify_main_cmdline(b"spicetify\0watch\0-s\0"));
        assert!(!is_spotify_main_cmdline(b""));
    }

    #[test]
    fn start_time_is_read_past_the_name() {
        // Field 22 is 8800; the name has a space and a `)` in it on purpose.
        let stat = "146085 (spi cetify)) S 1 146085 146085 0 -1 4194560 1 0 0 0 \
                    5 6 0 0 20 0 9 0 8800 1000 100";
        assert_eq!(start_time_of(stat), Some(8800));
        assert_eq!(start_time_of("146085 (spicetify) S 1"), None);
        assert_eq!(start_time_of(""), None);

        // And the live one parses: this very test is running.
        let own = fs::read_to_string("/proc/self/stat").unwrap();
        assert!(start_time_of(&own).is_some());
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
        assert_eq!(Mode::parse("season"), Some(Mode::Saison(Shade::Light)));
        assert_eq!(Mode::parse("season:dark"), Some(Mode::Saison(Shade::Dark)));
        assert_eq!(
            Mode::parse("season:light"),
            Some(Mode::Saison(Shade::Light))
        );
        assert_eq!(Mode::parse("season:auto"), Some(Mode::Saison(Shade::Auto)));
        assert_eq!(Mode::parse("season:"), None);
        assert_eq!(Mode::parse("season:dusk"), None);

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
        assert_eq!(Mode::parse("season"), Some(Mode::Saison(Shade::Light)));
    }

    #[test]
    fn season_shade_follows_the_clock_only_when_auto() {
        for hour in 0..24 {
            assert!(Shade::Dark.is_dark(hour));
            assert!(!Shade::Light.is_dark(hour));
        }
        // The same split as Time: day is light, sunset and night are dark.
        assert!(!Shade::Auto.is_dark(12));
        assert!(Shade::Auto.is_dark(19));
        assert!(Shade::Auto.is_dark(2));
    }

    #[test]
    fn season_shade_setting_is_read_from_the_settings() {
        let with = |theme: &str| serde_json::json!({"modes": {"seasonTheme": theme}});
        assert_eq!(season_shade_setting(Some(&with("dark"))), Shade::Dark);
        assert_eq!(season_shade_setting(Some(&with("auto"))), Shade::Auto);
        // `ask` has nobody to ask on a timer, and an old file has no key at all.
        assert_eq!(season_shade_setting(Some(&with("ask"))), Shade::Light);
        assert_eq!(season_shade_setting(None), Shade::Light);
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
        assert!(is_image(Path::new("foo.jpeg")));
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

        let pairs = vec![(img.clone(), kept.clone())];
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
