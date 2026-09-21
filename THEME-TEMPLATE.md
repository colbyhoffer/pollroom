# PollRoom theme template

Hand this file to Claude (or any designer) with a one-line brief like
*"fill this out as a neon arcade theme"* or *"make a corporate navy
theme for a McCombs event"*. The result is one JavaScript object you
paste into [`themes.js`](themes.js) — no other file changes.

A theme restyles all three surfaces at once: audience phones, the
presenter console, and the presentation screen. The presenter picks the
active theme in the console sidebar (Session panel → Theme) and it
applies live for everyone in the room.

## The template

Copy this, replace every `<...>`, and add it inside
`window.POLLROOM_THEMES = { ... }` in `themes.js` with a unique key:

```js
"<kebab-case-key>": {
  name: "<Display Name>",              // shown in the console's Theme picker
  vars: {
    bg:             "<page background>",
    card:           "<panel/card background, slightly raised from bg>",
    card2:          "<inputs, option buttons, bar tracks — one step further from bg>",
    line:           "<hairline borders between elements>",
    text:           "<primary text>",
    textSoft:       "<secondary text, e.g. poll subtitles — between text and muted>",
    muted:          "<labels, timestamps, helper text>",
    accent:         "<THE brand color: buttons, live pill, winner bar, join URL>",
    accentSoft:     "<accent at ~12-14% opacity, e.g. rgba(r,g,b,0.14) — selected/live fills>",
    accentFaint:    "<accent at ~7-10% opacity — the leader-card wash on stage>",
    accentEdge:     "<accent at ~40-45% opacity — pill and banner borders>",
    accentContrast: "<text color ON accent-filled buttons — near-black or white>",
    good:           "<positive signal: presence dot, success states>",
    danger:         "<destructive: delete buttons, expired timer>",
  },
  // Word clouds and result bars cycle these in order; first = the accent.
  // 6-8 colors, all clearly distinguishable from each other ON the bg color.
  ramp: ["<accent>", "<c2>", "<c3>", "<c4>", "<c5>", "<c6>", "<c7>", "<c8>"],
  font: {
    // Full CSS stack with real fallbacks. Google Fonts only.
    family: "'<Face>', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    googleFonts: "https://fonts.googleapis.com/css2?family=<Face>:wght@400;600;800;900&display=swap",
  },
  // QR module colors. dark = the modules, light = the QR card behind them.
  // Keep light near-white and dark near-black or codes stop scanning.
  qr: { dark: "<near-black, usually = bg of a dark theme or text of a light one>", light: "#ffffff" },
},
```

## Rules that make or break a theme

1. **Contrast is non-negotiable.** `text` on `bg` and on `card` must hit
   4.5:1; `muted` on `card` at least 4.5:1 (it carries timestamps and
   labels); `accentContrast` on `accent` at least 4.5:1 (button labels).
   The stage is read from 40 feet away — when in doubt, more contrast.
2. **The ramp lives on `bg`.** Every ramp color needs ~3:1 against `bg`
   (word clouds are bold text at many sizes). No two adjacent ramp
   colors should be confusable.
3. **Light themes work.** `card` lighter/whiter than `bg`, shadows-by-
   border via `line`, and `accentContrast` usually becomes `#ffffff` —
   check it against the accent (bold button text needs 3:1 minimum,
   4.5:1 preferred).
4. **Fonts:** weights 400/600/800/900 are all used — request them in the
   `googleFonts` URL. Display faces with tight bolds (Archivo, Sora,
   Space Grotesk, Bricolage Grotesque) suit the stage; avoid thin faces.
5. **Don't touch the key of an existing theme** — the selected theme is
   stored by key, and `"default"` must always exist.

## Installing a new theme

1. Paste the filled object into `themes.js` (comma-separated with the
   existing entries).
2. Commit and push — GitHub Pages redeploys in about a minute.
3. In the presenter console: Session panel → Theme → pick it. Audience
   phones and the stage restyle within seconds.

## Example

See `"longhorn-light"` in [`themes.js`](themes.js) — a filled-out
example of this template (warm paper ground, burnt-orange accent,
white-on-accent buttons, dark QR modules).
