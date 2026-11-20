# Sanity design language

The Dashboard (`Sources/Sanity/UI/Dashboard/DashboardView.swift`) is the
reference screen. Tokens and shared views live in
`Sources/Sanity/UI/Design/SanityDesign.swift`. When a new screen needs a
decision this page doesn't cover, copy what the Dashboard does.

## Principles

1. **One focal point per screen.** The Dashboard's is a single sentence about
   the Mac's health. Everything else supports it. A healthy state needs no
   ornament; only a problem earns an inline warning glyph.
2. **Native first.** Grouped `Form`s for settings, system controls, page
   names in the window title bar. Custom views only where macOS has no
   equivalent.
3. **Structure from space and hairlines, not boxes.** No cards, no tinted
   panels, no striped rows. A 1-pixel rule (`SanityHairline`) or a gap
   carries every separation.
4. **Colour means something.** Neutral by default. Green, orange and red mean
   health. Sanity Indigo means "this is Sanity / live data". Nothing else is
   coloured.
5. **Numbers tell the truth.** A caption never contradicts its figure, and a
   bar always shows the same quantity as the number above it.

## Identity

- **Sanity Indigo** (`SanityDesign.brand`): the planet mark, live history
  lines, setup links. Never status, never chrome, never large fills.
- **The planet mark** appears once per screen, small, beside the identity
  line, and as the Dashboard's sidebar icon.

## Type roles (`SanityDesign.Typography`)

| Role | Spec | Use |
|---|---|---|
| `display` | 22 pt semibold | The one sentence a screen leads with |
| `eyebrow` | 11 pt semibold, uppercase, 0.6 tracking, secondary | Section labels and the identity line only |
| reading label | 12 pt medium, sentence case, secondary | Labels above a single value |
| `metric` + `metricUnit` | 28 pt / 14 pt SF Pro Rounded, tabular | Readings: unit smaller and secondary |
| `section` | 13 pt semibold | Popover and inline titles |
| `body` / `secondary` / `caption` | 13 / 12 / 11 pt | Everything else |

## Grid and spacing

- Custom pages use the grouped-form column (`GroupedFormMetrics`): a
  704 pt-max column, 20 pt outer margin and a 10 pt row inset. Text on every
  page starts on the same line as form row labels.
- Spacing comes from a 4-point scale (`SanityDesign.Space`): 4, 8, 12, 16, 24, 32.
  Major sections on the Dashboard are 36 pt apart.

## Data display

- **Fast-changing values** (processor, memory, power) get a 22 pt history
  line in Sanity Indigo with a barely-there fill, which turns orange or red
  when unhealthy.
- **Capacities** (storage, battery) get a 3 pt bar showing **what is left**,
  neutral grey unless low.
- **Durations** use one style everywhere ("4d 3h", "2h 37m").
- **Values in one row** are separated by " · ", always with single spaces.
- **Loading** says "Sampling…" until real data arrives; never an empty state
  for data that is merely slow.
- **Process lists** show apps, merged by name. System daemons collapse into a
  single "Background processes" row.

## Interaction

- Double-click an app row to bring it forward. Right-click or hover to Quit.
- Sort and filter options are borderless menus in the section's label row.
- Disclosure labels use the eyebrow style with a trailing chevron.
- Inline actions read as a sentence: "0 of 4 done · Next step › · Hide", with
  the dismiss control beside what it dismisses, never pushed to the far edge.
- Honour Reduce Motion for every animation.

## Notch alerts

Sanity's notch alerts copy the iPhone Dynamic Island compact layout: same
height as the notch, a glyph left of the camera, one short word right of it,
equal sides, dimmed for "off" states (`SanityEventCompact`).
