# Design - Financial Tracker

A locked design system for this app. Every page redesign reads this file before
emitting code. Do not regenerate per page; extend or amend this file when the
system needs to grow.

## Genre
editorial

## Macrostructure family

- Marketing pages: not used in this app
- App pages: Brutal Newsprint Workbench - masthead ribbon, ruled-paper panels,
  thick borders, asymmetrical lead modules, compact ledger tables
- Content pages: not used in this app

## Theme

- `--color-paper` oklch(0.95 0.02 85)
- `--color-paper-2` oklch(0.91 0.025 85)
- `--color-paper-3` oklch(0.87 0.03 84)
- `--color-ink` oklch(0.22 0.02 40)
- `--color-ink-2` oklch(0.37 0.02 45)
- `--color-rule` oklch(0.52 0.02 60)
- `--color-accent` oklch(0.54 0.18 28)
- `--color-positive` oklch(0.56 0.12 145)
- `--color-negative` oklch(0.55 0.19 28)
- `--color-focus` oklch(0.47 0.11 250)

## Typography

- Display: system serif fallback stack, weight 800, style normal
- Body: system sans fallback stack, weight 500
- Mono: system mono fallback stack, weight 600
- Display tracking: -0.04em
- Type scale anchor: `display` = clamp(2.3rem, 4vw, 3.75rem)

## Spacing

4-point named scale. The values are implemented in the Flutter theme and shared
widgets. Pages must use named design primitives instead of ad hoc container
styling whenever possible.

## Motion

- Easings: sharp ease-out, sharp ease-in-out
- Reveal pattern: none by default; only subtle panel fade/lift where feedback is
  needed
- Reduced-motion fallback: opacity-only, short duration

## Microinteractions stance

- Silent success, never celebratory toast spam
- Hard focus rings and border swaps over glow effects
- Hover delay avoided; this is a tool, not a showroom

## CTA voice

- Primary CTA: filled ink or accent block, square corners, bold uppercase labels
- Secondary CTA: outlined paper cards with heavy borders

## Per-page allowances

- App pages must not use decorative illustration enrichment
- Data hierarchy and type contrast carry the visual load

## Charts

Charts belong to the same newsprint system as everything else (binding on the
Analytics work in `docs/PRD.md` §8):

- `fl_chart` only; square corners, strong ruled axes, warm paper background
- No gradients, glow, 3D, gauges, or decorative charts; one value axis per
  chart (never dual-axis)
- Ink for structure; accent/positive/negative only where a delta or state
  demands it; mono numerals for values
- Currency values and axis units always visible; tooltips carry full values
- Every chart ships an accessible text summary, a tabular alternative, and an
  empty state
- KPI numbers are metric strips/stat blocks, not mini-charts

## What Pages Must Share

- Warm paper background and dark ink shell
- Thick ruled borders and square corners
- Serif mastheads, sans body, mono numerals
- Accent colors only on deltas, warnings, and active controls
- Dense top-of-page summary band before longer content

## What Pages May Differ On

- Panel rhythm and split layout inside each page
- Whether the lead block is a summary slab, message wall, or ledger stack
- Use of accent bars or inverted ink blocks for a specific section

## Exports

### tokens.css

```css
:root {
  --color-paper: oklch(0.95 0.02 85);
  --color-paper-2: oklch(0.91 0.025 85);
  --color-paper-3: oklch(0.87 0.03 84);
  --color-ink: oklch(0.22 0.02 40);
  --color-ink-2: oklch(0.37 0.02 45);
  --color-rule: oklch(0.52 0.02 60);
  --color-accent: oklch(0.54 0.18 28);
  --color-positive: oklch(0.56 0.12 145);
  --color-negative: oklch(0.55 0.19 28);
  --color-focus: oklch(0.47 0.11 250);
}
```
