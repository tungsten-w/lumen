/* Lumen × Anki: the parts CSS cannot do alone.
 *
 * - numbers the deck rows, so they rise in one after another;
 * - recolours the stats page's review calendar, whose cells d3 fills with
 *   its own green scale, onto the palette's primary.
 * __init__.py calls `lumen.refresh()` after a live palette change. */
(function () {
  "use strict";
  if (window.lumen) return;

  const root = document.documentElement;

  // Tag the page from the <script> tag itself: Anki's pages forbid inline
  // scripts, and this runs in <head>, before anything is drawn.
  const tag = document.currentScript && document.currentScript.dataset.classes;
  if (tag) root.classList.add(...tag.split(" "));

  function staggerDecks() {
    document.querySelectorAll("tr.deck").forEach((row, i) => {
      row.style.setProperty("--i", Math.min(i, 24));
    });
  }

  // ── Calendar heatmap ───────────────────────────────────────────────

  // The calendar is the only graph drawn with hundreds of equal cells.
  const CALENDAR_CELLS = 200;

  function parse(colour) {
    const probe = document.createElement("span");
    probe.style.color = colour;
    document.body.appendChild(probe);
    const rgb = getComputedStyle(probe).color.match(/[\d.]+/g);
    probe.remove();
    return rgb ? rgb.slice(0, 3).map(Number) : null;
  }

  function lightnessAndSaturation([r, g, b]) {
    const max = Math.max(r, g, b) / 255;
    const min = Math.min(r, g, b) / 255;
    const l = (max + min) / 2;
    const s = max === min ? 0 : (max - min) / (1 - Math.abs(2 * l - 1));
    return [l, s];
  }

  const cache = new Map();

  function heat(fill) {
    if (cache.has(fill)) return cache.get(fill);
    const rgb = parse(fill);
    let out = null;
    if (rgb) {
      const [l, s] = lightnessAndSaturation(rgb);
      // Grey cells are days with nothing due: left as Anki draws them.
      if (s > 0.15) {
        // d3's scales run light (few reviews) to dark (many).
        const t = Math.max(0.12, Math.min(1, (0.92 - l) / 0.7));
        out = `color-mix(in oklab, var(--lm-primary) ${Math.round(t * 100)}%, var(--lm-surface-container-high))`;
      }
    }
    cache.set(fill, out);
    return out;
  }

  function recolourCalendars() {
    document.querySelectorAll("svg").forEach((svg) => {
      const cells = svg.querySelectorAll("rect[fill]");
      if (cells.length < CALENDAR_CELLS) return;
      cells.forEach((cell) => {
        const fill = cell.getAttribute("fill");
        if (cell.dataset.lumenFill === fill) return;
        cell.dataset.lumenFill = fill;
        const colour = heat(fill);
        cell.style.fill = colour || "";
        cell.style.rx = "2px";
      });
    });
  }

  let queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      if (root.classList.contains("lumen-deck-stats")) recolourCalendars();
    });
  }

  function refresh() {
    cache.clear();
    document.querySelectorAll("rect[data-lumen-fill]").forEach((cell) => {
      delete cell.dataset.lumenFill;
    });
    staggerDecks();
    schedule();
  }

  function start() {
    staggerDecks();
    schedule();
    // The deck list is redrawn in place, and the graphs as you change their
    // range, so keep watching.
    new MutationObserver(() => {
      staggerDecks();
      schedule();
    }).observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["fill"],
    });
  }

  window.lumen = { refresh };
  if (document.body) start();
  else document.addEventListener("DOMContentLoaded", start);
})();
