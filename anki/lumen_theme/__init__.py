"""Lumen for Anki: the wallpaper's palette, across all of Anki.

Noctalia rewrites `user_files/colors.css` on every wallpaper change, from the
template `noctalia-anki.css` beside this folder. This add-on

- remaps Anki's own colour variables onto that palette, in the web pages and
  in the Qt widgets alike, since both read the same `aqt.colors` table;
- injects `web/lumen.css` and `web/lumen.js` into every page Anki draws;
- lays the wallpaper, blurred, behind the main window, cut so the toolbar, the
  page and the bottom bar line up as one image;
- polls the palette and the wallpaper, and repaints everything live when
  either changes. Nothing needs a restart.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

from aqt import colors, gui_hooks, mw
from aqt.browser.previewer import Previewer
from aqt.clayout import CardLayout
from aqt.deckbrowser import DeckBrowser, DeckBrowserBottomBar
from aqt.overview import Overview, OverviewBottomBar
from aqt.qt import QEvent, QImage, QObject, Qt, QTimer, QWidget
from aqt.reviewer import Reviewer, ReviewerBottomBar
from aqt.theme import Theme, theme_manager
from aqt.toolbar import TopToolbar
from aqt.webview import AnkiWebView, WebContent

ADDON = mw.addonManager.addonFromModule(__name__)
HERE = Path(__file__).resolve().parent
USER_FILES = HERE / "user_files"
PALETTE_FILE = USER_FILES / "colors.css"
FALLBACK_PALETTE = HERE / "web" / "fallback-colors.css"
WALL_FILE = USER_FILES / "wall.jpg"

# Lumen keeps this link on the wallpaper it last set, and a flat PNG of its
# first frame in /tmp for the ones Qt cannot open (a video, say).
WALL_LINK = Path.home() / "Pictures/Wallpapers/current_wallpaper.jpg"
WALL_STILL = Path("/tmp/current_wallpaper.png")
WALL_WIDTH = 1920

mw.addonManager.setWebExports(__name__, r"(web|user_files)/.*\.(css|js|jpg)")

DEFAULTS: dict[str, Any] = {
    "wallpaper": False,
    "wallpaper_blur": 24,
    "wallpaper_dim": 0.62,
    "follow_lumen_mode": True,
    "restyle_cards": True,
    "font": "Adwaita Sans",
    "card_font": "Adwaita Sans",
    "animations": True,
    "qt_theme": True,
    "poll_ms": 1500,
}


def config() -> dict[str, Any]:
    return {**DEFAULTS, **(mw.addonManager.getConfig(__name__) or {})}


# ── Palette ───────────────────────────────────────────────────────────

LINE = re.compile(r"--lm-([a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})\s*;")

# Anki's colour table, by the names `aqt.colors` gives it, onto the palette.
# A pair is a palette colour and the opacity to lay it down at.
ANKI_COLOURS: dict[str, str | tuple[str, float]] = {
    "FG": "on-surface",
    "FG_SUBTLE": "on-surface-variant",
    "FG_DISABLED": "outline",
    "FG_FAINT": "outline-variant",
    "FG_LINK": "primary",
    "CANVAS": "surface",
    "CANVAS_ELEVATED": "surface-container",
    "CANVAS_INSET": "surface-container-low",
    "CANVAS_OVERLAY": "surface-container-high",
    "CANVAS_CODE": "surface-container-lowest",
    "CANVAS_GLASS": ("surface-container", 0.45),
    "BORDER": "outline-variant",
    "BORDER_SUBTLE": "surface-container-highest",
    "BORDER_STRONG": "outline",
    "BORDER_FOCUS": "primary",
    "BUTTON_BG": "surface-container-high",
    "BUTTON_GRADIENT_START": "surface-container-highest",
    "BUTTON_GRADIENT_END": "surface-container-high",
    "BUTTON_HOVER_BORDER": "primary",
    "BUTTON_DISABLED": ("surface-container-high", 0.5),
    "BUTTON_PRIMARY_BG": "primary",
    "BUTTON_PRIMARY_GRADIENT_START": "primary",
    "BUTTON_PRIMARY_GRADIENT_END": "primary",
    "BUTTON_PRIMARY_DISABLED": ("primary", 0.45),
    "SCROLLBAR_BG": "outline-variant",
    "SCROLLBAR_BG_HOVER": "outline",
    "SCROLLBAR_BG_ACTIVE": "primary",
    "SHADOW": ("shadow", 0.45),
    "SHADOW_INSET": ("shadow", 0.35),
    "SHADOW_SUBTLE": ("shadow", 0.2),
    "SHADOW_FOCUS": "primary",
    "ACCENT_CARD": "primary",
    "ACCENT_NOTE": "secondary",
    "ACCENT_DANGER": "error",
    "STATE_NEW": "secondary",
    "STATE_LEARN": "tertiary",
    "STATE_REVIEW": "primary",
    "HIGHLIGHT_BG": ("primary", 0.35),
    "HIGHLIGHT_FG": "on-surface",
    "SELECTED_BG": "secondary-container",
    "SELECTED_FG": "on-secondary-container",
}


def read_palette() -> dict[str, str]:
    for path in (PALETTE_FILE, FALLBACK_PALETTE):
        try:
            found = dict(LINE.findall(path.read_text()))
        except OSError:
            continue
        if "surface" in found and "primary" in found:
            return found
    return {}


def rgba(hex_colour: str, alpha: float) -> str:
    r, g, b = (int(hex_colour[i : i + 2], 16) for i in (1, 3, 5))
    # The spacing and the decimals are what `ThemeManager.qcolor` parses.
    return f"rgba({r}, {g}, {b}, {alpha:.2f})"


def anki_colours(palette: dict[str, str]) -> dict[str, str]:
    out = {}
    for name, source in ANKI_COLOURS.items():
        key, alpha = source if isinstance(source, tuple) else (source, None)
        if key in palette:
            out[name] = palette[key] if alpha is None else rgba(palette[key], alpha)
    return out


def is_dark(palette: dict[str, str]) -> bool:
    surface = palette.get("surface", "#000000")
    r, g, b = (int(surface[i : i + 2], 16) / 255 for i in (1, 3, 5))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5


# ── State ─────────────────────────────────────────────────────────────


class State:
    palette: dict[str, str] = {}
    palette_mtime = 0.0
    palette_css = ""
    wall_key = ""
    wall_size: tuple[int, int] | None = None
    wall_version = 0
    original: dict[str, dict[str, str]] = {}


state = State()


def load_palette() -> bool:
    "Read the palette into `state`. True when it changed."
    try:
        mtime = PALETTE_FILE.stat().st_mtime
    except OSError:
        mtime = -1.0
    if mtime == state.palette_mtime and state.palette:
        return False
    state.palette_mtime = mtime
    palette = read_palette()
    if not palette or palette == state.palette:
        return False
    state.palette = palette
    state.palette_css = page_vars_css(palette)
    if config()["qt_theme"]:
        recolour_anki(palette)
    return True


def recolour_anki(palette: dict[str, str]) -> None:
    """Point `aqt.colors` at the palette, light and dark alike.

    The palette is already the one for the mode Lumen is in, so both slots
    get it; `follow_lumen_mode` then picks which slot Anki reads."""
    for name, value in anki_colours(palette).items():
        table = getattr(colors, name, None)
        if not isinstance(table, dict):
            continue
        state.original.setdefault(name, {k: table[k] for k in ("light", "dark")})
        table["light"] = value
        table["dark"] = value


def page_vars_css(palette: dict[str, str]) -> str:
    cfg = config()
    lines = [f"--lm-{k}: {v};" for k, v in palette.items()]
    for name, value in anki_colours(palette).items():
        lines.append(f"--{name.lower().replace('_', '-')}: {value};")
    lines.append(f"--lm-font: {css_font(cfg['font'])};")
    lines.append(f"--lm-card-font: {css_font(cfg['card_font'])};")
    lines.append(f"--lm-dim: {float(cfg['wallpaper_dim']):.2f};")
    # `:not(#lumen)` lifts this above every `:root` / `.night-mode` rule Anki
    # and its pages declare, wherever in the page they come.
    return ":root:not(#lumen) {\n  " + "\n  ".join(lines) + "\n}"


def css_font(name: str) -> str:
    name = str(name).replace('"', "")
    return f'"{name}", "Inter", "Adwaita Sans", sans-serif' if name else "inherit"


# ── Wallpaper ─────────────────────────────────────────────────────────


def wallpaper_source() -> Path | None:
    try:
        target = WALL_LINK.resolve(strict=True)
    except OSError:
        target = None
    if target and not QImage(str(target)).isNull():
        return target
    return WALL_STILL if WALL_STILL.is_file() else None


def load_wallpaper() -> bool:
    "Blur the current wallpaper into `user_files`. True when it changed."
    cfg = config()
    if not cfg["wallpaper"]:
        changed = state.wall_size is not None
        state.wall_size = None
        state.wall_key = ""
        return changed
    try:
        target = WALL_LINK.resolve(strict=True)
        key = f"{target}:{target.stat().st_mtime}:{cfg['wallpaper_blur']}"
    except OSError:
        key = f"still:{WALL_STILL.stat().st_mtime if WALL_STILL.exists() else 0}"
    if key == state.wall_key:
        return False
    state.wall_key = key

    source = wallpaper_source()
    image = QImage(str(source)) if source else QImage()
    if image.isNull():
        changed = state.wall_size is not None
        state.wall_size = None
        return changed

    smooth = Qt.TransformationMode.SmoothTransformation
    if image.width() > WALL_WIDTH:
        image = image.scaledToWidth(WALL_WIDTH, smooth)
    image = blurred(image, int(cfg["wallpaper_blur"]))
    USER_FILES.mkdir(exist_ok=True)
    image.save(str(WALL_FILE), "JPG", 90)
    state.wall_size = (image.width(), image.height())
    state.wall_version += 1
    return True


def blurred(image: QImage, radius: int) -> QImage:
    """A cheap, soft blur: shrink, then grow back in steps.

    Done once per wallpaper, so the pages only ever draw a flat image; a CSS
    `filter: blur()` that size would be redone on every repaint."""
    if radius <= 0:
        return image
    smooth = Qt.TransformationMode.SmoothTransformation
    width = image.width()
    small = image.scaledToWidth(max(16, width * 3 // radius), smooth)
    while small.width() * 2 < width:
        small = small.scaledToWidth(small.width() * 2, smooth)
    return small.scaledToWidth(width, smooth)


def wall_css(web: AnkiWebView | None) -> str:
    """Size and place the wallpaper in `web` so that, across the main window's
    webviews, it reads as one image covering the whole window."""
    if not state.wall_size or web is None or not in_main_window(web):
        return ""
    iw, ih = state.wall_size
    W, H = max(1, mw.width()), max(1, mw.height())
    scale = max(W / iw, H / ih)
    bw, bh = iw * scale, ih * scale
    origin = web.mapTo(mw, web.rect().topLeft())
    zoom = web.zoomFactor() or 1
    x = ((W - bw) / 2 - origin.x()) / zoom
    y = ((H - bh) / 2 - origin.y()) / zoom
    url = f"/_addons/{ADDON}/user_files/wall.jpg?v={state.wall_version}"
    return (
        ":root:not(#lumen) {"
        f' --lm-wall: url("{url}");'
        f" --lm-wall-size: {bw / zoom:.1f}px {bh / zoom:.1f}px;"
        f" --lm-wall-pos: {x:.1f}px {y:.1f}px; }}"
    )


def in_main_window(web: QWidget) -> bool:
    return web in (mw.web, mw.toolbarWeb, mw.bottomWeb)


# ── Pages ─────────────────────────────────────────────────────────────


def page_of(context: Any) -> tuple[str, AnkiWebView | None]:
    "Which page a `stdHtml` call draws, and in which webview."
    if isinstance(context, DeckBrowser):
        return "deckbrowser", mw.web
    if isinstance(context, Overview):
        return "overview", mw.web
    if isinstance(context, Reviewer):
        return "reviewer card", mw.web
    if isinstance(context, TopToolbar):
        return "toolbar", mw.toolbarWeb
    if isinstance(context, ReviewerBottomBar):
        return "reviewer-bottom bottom", mw.bottomWeb
    if isinstance(context, (DeckBrowserBottomBar, OverviewBottomBar)):
        return "bottom", mw.bottomWeb
    if isinstance(context, Previewer):
        return "previewer card", None
    if isinstance(context, CardLayout):
        return "card-layout", None
    return "page", None


def html_classes(page: str, web: AnkiWebView | None) -> list[str]:
    cfg = config()
    classes = ["lumen"] + [f"lumen-{p}" for p in page.split()]
    if web is not None and in_main_window(web):
        classes.append("lumen-main")
        if state.wall_size:
            classes.append("lumen-wall")
    if cfg["restyle_cards"]:
        classes.append("lumen-cards")
    if cfg["animations"]:
        classes.append("lumen-motion")
    return classes


def asset(name: str) -> str:
    try:
        version = int((HERE / "web" / name).stat().st_mtime)
    except OSError:
        version = 0
    return f"/_addons/{ADDON}/web/{name}?v={version}"


def on_set_content(web_content: WebContent, context: Any) -> None:
    load_palette()
    page, web = page_of(context)
    classes = html_classes(page, web)
    web_content.head += f"""
<style id="lumen-palette">{state.palette_css}</style>
<style id="lumen-wall">{wall_css(web)}</style>
<link rel="stylesheet" id="lumen-css" href="{asset('lumen.css')}">
<script src="{asset('lumen.js')}" data-classes="{' '.join(classes)}"></script>"""


def on_page_styled(web: AnkiWebView) -> None:
    """SvelteKit pages (deck options, stats, congratulations, the editor…)
    never go through `stdHtml`; they are dressed here once they load."""
    url = web.url().toString()
    if web is mw.web and "congrats" in url:
        page = "congrats"
    else:
        page = web.kind.value.replace(" ", "-")
    web.eval(update_js(web, html_classes(page, web)))


def update_js(web: AnkiWebView, classes: list[str] | None = None) -> str:
    "Create or refresh Lumen's styles in a page that is already showing."
    payload = {
        "palette": state.palette_css,
        "wall": wall_css(web),
        "css": asset("lumen.css"),
        "js": asset("lumen.js"),
        "classes": classes,
        "hasWall": bool(state.wall_size) and in_main_window(web),
    }
    return f"""(function(p) {{
  const head = document.head || document.documentElement;
  function style(id, text) {{
    let el = document.getElementById(id);
    if (!el) {{ el = document.createElement("style"); el.id = id; head.appendChild(el); }}
    el.textContent = text;
  }}
  style("lumen-palette", p.palette);
  style("lumen-wall", p.wall);
  let link = document.getElementById("lumen-css");
  if (!link) {{ link = document.createElement("link"); link.id = "lumen-css"; link.rel = "stylesheet"; head.appendChild(link); }}
  if (link.getAttribute("href") !== p.css) link.setAttribute("href", p.css);
  const root = document.documentElement.classList;
  if (p.classes) root.add(...p.classes);
  if (root.contains("lumen-main")) root.toggle("lumen-wall", p.hasWall);
  if (!window.lumen) {{
    const s = document.createElement("script"); s.src = p.js; head.appendChild(s);
  }} else if (window.lumen.refresh) window.lumen.refresh();
}})({json.dumps(payload)});"""


def webviews() -> list[AnkiWebView]:
    return [w for w in mw.app.allWidgets() if isinstance(w, AnkiWebView)]


def push_wall() -> None:
    for web in (mw.toolbarWeb, mw.web, mw.bottomWeb):
        if web is not None:
            web.eval(
                "(function(t){const el=document.getElementById('lumen-wall');"
                f"if(el)el.textContent=t;}})({json.dumps(wall_css(web))});"
            )


def push_all() -> None:
    for web in webviews():
        try:
            web.eval(update_js(web))
        except RuntimeError:
            pass  # deleted underneath us


# ── Qt ────────────────────────────────────────────────────────────────


def on_style(buf: str) -> str:
    p = state.palette
    if not config()["qt_theme"] or not p:
        return buf
    return (
        buf
        + f"""
QMenu {{ border: 1px solid {p['outline-variant']}; padding: 6px; }}
QMenu::item {{ border-radius: 8px; padding: 6px 22px 6px 14px; }}
QMenu::item:selected {{ background: {p['secondary-container']}; color: {p['on-secondary-container']}; }}
QMenu::separator {{ height: 1px; background: {p['outline-variant']}; margin: 4px 8px; }}
QMenuBar::item:selected {{ background: {p['secondary-container']}; color: {p['on-secondary-container']}; border-radius: 6px; }}
QToolTip {{ background: {p['surface-container-high']}; color: {p['on-surface']};
    border: 1px solid {p['outline-variant']}; border-radius: 8px; padding: 4px 8px; }}
QLineEdit:focus, QTextEdit:focus, QPlainTextEdit:focus, QSpinBox:focus {{ border: 1px solid {p['primary']}; }}
QProgressBar {{ background: {p['surface-container-high']}; border: none; border-radius: 6px;
    text-align: center; color: {p['on-surface']}; }}
QProgressBar::chunk {{ background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
    stop:0 {p['primary']}, stop:1 {p['secondary']}); border-radius: 6px; }}
QTreeView::item:selected, QListView::item:selected, QTableView::item:selected {{
    background: {p['secondary-container']}; color: {p['on-secondary-container']}; }}
"""
    )


def apply_mode_and_qt() -> None:
    "Follow Lumen's light/dark, then redraw the Qt side with the palette."
    cfg = config()
    if cfg["follow_lumen_mode"] and state.palette:
        wanted = Theme.DARK if is_dark(state.palette) else Theme.LIGHT
        if mw.pm.theme() != wanted:
            mw.pm.set_theme(wanted)
            theme_manager.apply_style()  # redraws Qt and every page's classes
            return
    if cfg["qt_theme"]:
        theme_manager._apply_palette(mw.app)
        theme_manager._apply_style(mw.app)
        gui_hooks.theme_did_change()


# ── Watching ──────────────────────────────────────────────────────────


class Watcher(QObject):
    "Polls palette and wallpaper, and keeps the wallpaper aligned on resize."

    def __init__(self) -> None:
        super().__init__(mw)
        self.poll = QTimer(self)
        self.poll.timeout.connect(self.check)
        self.poll.start(int(config()["poll_ms"]))
        self.realign = QTimer(self)
        self.realign.setSingleShot(True)
        self.realign.setInterval(30)
        self.realign.timeout.connect(push_wall)
        for widget in (mw, mw.web, mw.toolbarWeb, mw.bottomWeb):
            widget.installEventFilter(self)

    def eventFilter(self, obj: QObject | None, event: QEvent | None) -> bool:
        if event is not None and event.type() in (QEvent.Type.Resize, QEvent.Type.Move):
            self.realign.start()
        return False

    def check(self) -> None:
        palette = load_palette()
        wall = load_wallpaper()
        if palette:
            apply_mode_and_qt()
        if palette or wall:
            push_all()


watcher: Watcher | None = None


def on_profile_open() -> None:
    global watcher
    load_palette()
    load_wallpaper()
    apply_mode_and_qt()
    if watcher is None:
        watcher = Watcher()
    # The main window drew before the wallpaper was ready.
    mw.progress.single_shot(50, push_all)


# Before any window is styled, so Anki's own first `apply_style` already
# draws in the palette.
load_palette()

gui_hooks.webview_will_set_content.append(on_set_content)
gui_hooks.webview_did_inject_style_into_page.append(on_page_styled)
gui_hooks.style_did_init.append(on_style)
gui_hooks.profile_did_open.append(on_profile_open)
