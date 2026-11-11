# Design system

Own name, palette, type and icons. No third-party branding (no sportsbook logos, team logos or player photos; generated monogram badges instead, with optional `logo_url` / `photo_url` for licensed images supplied by a self-hoster).

## Rules we follow
- **Type:** Bricolage Grotesque (headings, big numbers) with Hanken Grotesk (interface). No Inter, Roboto or Arial. Numbers use tabular figures.
- **Colour:** OKLCH themes (`propscope-dark` default, `propscope-light`) defined in `app/assets/tailwind/application.css` for daisyUI. Aquamarine accent; hit = green, miss = red, push = amber, EV = blue. No indigo or violet, no gradient splashes, no glowing borders. Generated badge hues are kept to 10 to 215 degrees.
- **Surfaces:** calibrated teal-slate scale. Never pure black or pure white.
- **Structure:** no cards inside cards (tables inside a card use dividers, not a second box), no eyebrow text, no pricing-style grids, no decorative emoji.
- **Motion:** colour transitions only (`transition-colors`, 150ms ease-out). No `transition: all`, no bounce.
- **Type floor:** nothing below 11px (`text-2xs`). Book codes, hit-rate labels and sample counts all use it; no arbitrary `text-[9px]` sizes. The 20px and 16px team markers carry no letters (the abbreviation is always beside them as text).
- **Contrast:** a hit-rate number is the tone colour mixed into the foreground (`hit_rate_cell_style`), never the raw tone colour on its own tint, and the tint is capped (`HIT_TINT_MAX`). Check new coloured cells with the detector, not by eye.
- **Reduced motion:** movement is removed, colour changes stay (they are the state cue).
- **Touch:** icon buttons are at least 40px; keyboard users get a skip link.

## daisyUI
daisyUI 5 is a Tailwind plugin, vendored as `app/assets/tailwind/daisyui.mjs` and `daisyui-theme.mjs` (no node needed). Components in use: `btn`, `card`, `tabs`, `modal`, `collapse`. Our semantic Tailwind names (`bg-surface`, `text-hit`, `text-muted`) are aliases of the daisyUI theme tokens, so the theme is the single source of truth.
