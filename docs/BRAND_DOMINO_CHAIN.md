# Domino Chain — brand assets

Single source for icons and wordmark references across Web + Android.

## Master

- **Full sheet** (Gemini / Keynote with grid, size variants, etc.) → automatic extraction of the glyph only:
  1. `python3 scripts/extract_domino_chain_mark.py --input <full-sheet.png> --output backend/app/assets/images/domino-chain-mark-extracted.png`
  2. `scripts/regenerate_domino_chain_assets.sh` (recalcule `domino-chain-logo.png`, `backend/public/icon*.png`, favicon, foreground Android).
- The script detects **cyan / violet** logo pixels, keeps the **largest connected component** (= the main center block), then crops with padding — without manual trimming.
- **Extracted reference** committed: `backend/app/assets/images/domino-chain-mark-extracted.png` (tight PNG around the "D").
- Vector favicon / SVG tab icon: `backend/public/icon.svg` (simplified vector approximation of the same motif for SVG favicon).

## Web (`backend/public/`)

| File | Use |
|------|-----|
| `icon.svg` | Primary vector favicon (`type="image/svg+xml"`). |
| `favicon.ico` | Legacy browsers; multi-size ICO from `icon.png`. |
| `icon.png` | 512×512 — PWA, `apple-touch-icon`. |
| `icon-192.png` | PWA install / manifest. |
| `icon-maskable.png` | 512×512 — `purpose: maskable`, content padded ~80% safe zone. |
| `favicons/` | Complete favicon pack (`16/32/48/64/96`, `icon-192`, `icon-512`, `apple-touch-icon`, `site.webmanifest`). |

Manifest: `backend/app/views/pwa/manifest.json.erb`.  
Layout links: `backend/app/views/layouts/application.html.erb`.

## Rails UI logo

- `backend/app/assets/images/domino-chain-logo.png` — headers, auth, beta sidebar (`image_tag "domino-chain-logo.png"`).

## Android (`android/app/src/main/res/`)

| Resource | Use |
|-----------|-----|
| `mipmap-*/ic_launcher.png` + `ic_launcher_round.png` | Launcher raster assets per density. |
| `mipmap-*/ic_launcher_foreground.png` | Adaptive icon foreground raster per density. |
| `mipmap-anydpi-v26/ic_launcher.xml` | Adaptive icon declaration (includes monochrome). |
| `values/ic_launcher_background.xml` | Adaptive icon background color. |
| `drawable/ic_notification.xml` | Notification icon vector source. |
| `drawable-*/ic_notification.png` | Notification raster fallbacks per density. |

Staging no longer overrides the launcher foreground so dev/prod share the same Domino Chain artwork.

## Tiny sizes

- **Favicon / SVG**: simplified geometry, high contrast.
- **Notification**: filled “D” silhouette only (`ic_notification.xml`), no gradient.

## Naming

- Product name: **Domino Chain** (app label, PWA `name`, notification titles, default HTML `<title>`).
