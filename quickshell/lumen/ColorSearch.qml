pragma Singleton

import QtQuick
import Quickshell

/// Colour search: picks the colour words out of a query and scores how well a
/// wallpaper's palette — the `colors` `lumen` reads off each thumbnail — fits
/// them.
///
/// Everything is compared in OKLCh rather than RGB, because there the hue of
/// a colour stays put while it gets darker or greyer: a navy night sky and a
/// bright sky blue are the same hue, which is exactly what "blue" means.
Singleton {
    id: root

    /// Hues in OKLCh degrees. `minL` / `maxL` narrow a word to a lightness band
    /// where the hue alone is not enough: brown is a dark orange, pink a light red.
    /// The achromatic words have no hue; `sim` below handles them by name.
    readonly property var vocabulary: ({
            red: { hue: 29 },
            orange: { hue: 55 },
            gold: { hue: 85 },
            yellow: { hue: 105 },
            green: { hue: 142 },
            teal: { hue: 185 },
            cyan: { hue: 200 },
            blue: { hue: 262 },
            purple: { hue: 305 },
            violet: { hue: 300 },
            magenta: { hue: 330 },
            pink: { hue: 355, minL: 0.62 },
            brown: { hue: 60, maxL: 0.5 },
            black: { achromatic: "black" },
            white: { achromatic: "white" },
            grey: { achromatic: "grey" },
            gray: { achromatic: "grey" },
            // French, since lumen speaks it too.
            rouge: { hue: 29 },
            jaune: { hue: 105 },
            vert: { hue: 142 },
            bleu: { hue: 262 },
            rose: { hue: 355, minL: 0.62 },
            marron: { hue: 60, maxL: 0.5 },
            noir: { achromatic: "black" },
            blanc: { achromatic: "white" },
            gris: { achromatic: "grey" }
        })

    /// What each word looks like on the chip in the search field.
    readonly property var swatches: ({
            red: "#e5484d", orange: "#f76b15", gold: "#d6a23a", yellow: "#f5d90a",
            green: "#46a758", teal: "#12a594", cyan: "#00a2c7", blue: "#3e63dd",
            purple: "#8e4ec6", violet: "#6e56cf", magenta: "#d6409f", pink: "#f4a6c8",
            brown: "#8a5a3c", black: "#111111", white: "#f5f5f5", grey: "#8b8d98",
            gray: "#8b8d98", rouge: "#e5484d", jaune: "#f5d90a", vert: "#46a758",
            bleu: "#3e63dd", rose: "#f4a6c8", marron: "#8a5a3c", noir: "#111111",
            blanc: "#f5f5f5", gris: "#8b8d98"
        })

    /// Reads one query term as a colour, or returns null if it is not one.
    /// `#orange` counts — that is how wallreco spells its tags — and so does a
    /// literal `#rrggbb` / `#rgb`.
    function parse(term: string): var {
        const word = term.startsWith("#") ? term.slice(1) : term;
        if (root.vocabulary[word] !== undefined)
            return { word: word, swatch: root.swatches[word], target: root.vocabulary[word] };
        if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/.test(term)) {
            const hex = term.length === 4 ? "#" + term[1] + term[1] + term[2] + term[2] + term[3] + term[3] : term;
            return { word: hex, swatch: hex, target: { lab: root.oklab(hex) } };
        }
        return null;
    }

    /// `#rrggbb` → OKLab `{ L, a, b }`, plus the polar `C` and `h` (degrees).
    function oklab(hex: string): var {
        const lin = c => {
            c /= 255;
            return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        };
        const r = lin(parseInt(hex.slice(1, 3), 16));
        const g = lin(parseInt(hex.slice(3, 5), 16));
        const b = lin(parseInt(hex.slice(5, 7), 16));

        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);

        const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
        const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
        const h = Math.atan2(B, A) * 180 / Math.PI;
        return { L: L, a: A, b: B, C: Math.hypot(A, B), h: h < 0 ? h + 360 : h };
    }

    /// How much one palette colour looks like `target`, from 0 to 1.
    function sim(c: var, target: var): real {
        if (target.lab) {
            const t = target.lab;
            const distance = Math.hypot(c.L - t.L, c.a - t.a, c.b - t.b);
            return Math.exp(-Math.pow(distance / 0.1, 2));
        }

        // 0 for a grey, 1 from a clearly coloured 0.08 chroma up.
        const colourful = Math.max(0, Math.min(1, (c.C - 0.02) / 0.06));

        switch (target.achromatic) {
        case "black":
            return Math.exp(-Math.pow(c.L / 0.25, 2));
        case "white":
            return Math.exp(-Math.pow((1 - c.L) / 0.15, 2)) * (1 - 0.7 * colourful);
        case "grey":
            return (1 - colourful) * Math.exp(-Math.pow((c.L - 0.6) / 0.25, 2));
        }

        let dh = Math.abs(c.h - target.hue) % 360;
        if (dh > 180)
            dh = 360 - dh;
        let score = colourful * Math.exp(-Math.pow(dh / 28, 2));
        if (target.maxL !== undefined && c.L > target.maxL)
            score *= Math.exp(-Math.pow((c.L - target.maxL) / 0.1, 2));
        if (target.minL !== undefined && c.L < target.minL)
            score *= Math.exp(-Math.pow((target.minL - c.L) / 0.1, 2));
        return score;
    }

    /// How well a whole palette fits one colour. Shares are square-rooted so an
    /// accent covering a few percent still counts — "red" should find the
    /// wallpaper with the red lantern, not only the ones that are mostly red.
    function fit(palette: var, target: var): real {
        let total = 0;
        let weights = 0;
        for (const colour of palette) {
            const weight = Math.sqrt(colour.weight);
            total += weight * root.sim(colour.lab, target);
            weights += weight;
        }
        return weights > 0 ? total / weights : 0;
    }

    /// The palette with its OKLab values worked out, so a search does the
    /// conversion once per wallpaper rather than once per keystroke.
    function prepare(colors: var): var {
        return (colors ?? []).map(colour => ({ weight: colour.weight, lab: root.oklab(colour.hex) }));
    }
}
