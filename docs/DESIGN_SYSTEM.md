# Domino Chain Design System

Unified design system for web (Rails) and Android app. Inspired by Blade Runner 2049 — dark, atmospheric, with a primary magenta accent and blue/violet secondary accents.

---

## Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `bg` | `#0e0e12` | Main background |
| `surface` | `#16161b` | Cards, blocks |
| `surface-elevated` | `#1e1e24` | Elevated surfaces |
| `border` | `#34343b` | Borders |
| `text` | `#fbfaf7` | Primary text |
| `text-muted` | `#c4c1bc` | Labels, secondary text |
| `text-dim` | `#8e8b87` | Tertiary text |
| `magenta` | `#ec4899` | Primary / CTA |
| `magenta-dim` | `#db2777` | Primary hover |
| `blue` | `#22d3ee` | Links, accents, focus |
| `blue-dim` | `#06b6d4` | Blue hover |
| `violet` | `#a855f7` | Secondary / premium |
| `violet-dim` | `#9333ea` | Secondary hover |
| `error` | `#ef6b6b` | Errors |
| `success` | `#22d3ee` | Success (aligned with blue accent) |

> Compatibility: `amber` and `teal` remain available as legacy aliases to `magenta` and `blue`.

---

## Typography

- **Font** : Space Grotesk (web), Roboto (Android)
- **Title** : 1.75rem / 28sp, web weight 500 (`-0.015em`), Android weight 300 (`0.08em`)
- **Subtitle** : 0.875rem / 14sp
- **Body** : 0.95rem / 15sp
- **Small** : 0.825rem / 13sp
- **Tiny** : 0.72rem / 11sp

---

## Spacing (dp / rem)

| Token | Web | Android |
|-------|-----|---------|
| xs | 0.25rem | 4dp |
| sm | 0.5rem | 8dp |
| md | 0.75rem | 12dp |
| lg | 1rem | 16dp |
| xl | 1.5rem | 24dp |
| 2xl | 2rem | 32dp |
| 3xl | 2.5rem | 40dp |

---

## Radius

- **sm** : 4dp
- **md** : 6dp
- **lg** : 8dp

---

## Components

### Buttons / CTA

| Variant | Usage |
|---------|-------|
| `primary` | Primary action (magenta) |
| `secondary` | Secondary action (magenta outline) |
| `ghost` | Links, tertiary actions (blue) |
| `sm` | Small format |

### Forms

- **Form group**: `ds-form-group` — spacing between fields
- **Label**: `ds-form-label` — small, text-muted
- **Input**: `ds-input` — `bg` background, `border` border, blue focus
- **Textarea**: `ds-input ds-textarea`
- **Hint**: `ds-form-hint` — helper text

### Sections

- **Section title**: `ds-section-title` — uppercase, letter-spacing, text-muted

### Flash / Feedback

- **Success**: translucent accent background, success border
- **Error**: translucent red background, error border

### Badges / Status / Toggles

- **Badge / status**: `ds-badge`, `ds-status` + variants (`--on`, `--off`, `--pending`, `--error`, `--locked`, `--live`)
- **Toggle**: `ds-toggle` and variants (`ds-toggle--on`) or DS components embedding it (`ds-beta-catalog-toggle-*`)
- **Activation color**: toggles, checkboxes, radios, and equivalent controls use `magenta`.
- **Clickable icons**: icon-only actions (for example settings, refresh, open/share/copy) use primary `magenta`.
- **Rule**: keep DS variants; do not restyle locally per page.

---

## Page Structure (Web)

```erb
<div class="ds-page">
  <div class="ds-container">
    <header class="ds-header">...</header>
    <!-- content -->
  </div>
</div>
```

## Screen Structure (Android)

- `ds_page`: root layout with padding
- `ds_section`: block with spacing
- `ds_card`: card with surface, border, radius

## Logos / Favicons / App icons

- **Web favicons** : `backend/public/favicons/` (`favicon-16/32/48/64/96`, `icon-192`, `icon-512`, `apple-touch-icon`, `site.webmanifest`)
- **Web mark SVG** : `backend/public/icon.svg`
- **Android launcher** : `android/app/src/main/res/mipmap-*/ic_launcher*.png` + `mipmap-anydpi-v26/ic_launcher*.xml`
- **Android notification** : `android/app/src/main/res/drawable/ic_notification.xml` (+ fallback PNGs `drawable-*/ic_notification.png`)
- **Launcher background** : `android/app/src/main/res/values/ic_launcher_background.xml`

---

## References

- **Web** : `backend/app/assets/stylesheets/design_system/`
- **Android** : `android/app/src/main/res/values/` (colors, themes, styles, dimens)
- **Brand assets** : `docs/BRAND_DOMINO_CHAIN.md`
