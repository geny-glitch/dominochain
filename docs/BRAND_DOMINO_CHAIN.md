# Domino Chain — brand assets

Single source for icons and wordmark references across Web + Android.

## Master

- **Feuille complète** (Gemini / keynote avec grille, variantes de taille, etc.) → extraction automatique du glyphe uniquement :
  1. `python3 scripts/extract_domino_chain_mark.py --input <full-sheet.png> --output backend/app/assets/images/domino-chain-mark-extracted.png`
  2. `scripts/regenerate_domino_chain_assets.sh` (recalcule `domino-chain-logo.png`, `backend/public/icon*.png`, favicon, foreground Android).
- Le script détecte les pixels **cyan / violet** du logo, prend la **plus grande composante connexe** (= le bloc principal au milieu), puis crop avec padding — sans avoir à découper à la main.
- **Référence extraite** commitée : `backend/app/assets/images/domino-chain-mark-extracted.png` (PNG serré sur le « D »).
- Vector favicon / SVG tab icon : `backend/public/icon.svg` (approximation vectorielle simplifiée du même motif pour favicon SVG).

## Web (`backend/public/`)

| File | Use |
|------|-----|
| `icon.svg` | Primary vector favicon (`type="image/svg+xml"`). |
| `favicon.ico` | Legacy browsers; multi-size ICO from `icon.png`. |
| `icon.png` | 512×512 — PWA, `apple-touch-icon`. |
| `icon-192.png` | PWA install / manifest. |
| `icon-maskable.png` | 512×512 — `purpose: maskable`, content padded ~80% safe zone. |
| `favicons/` | Pack favicon complet (`16/32/48/64/96`, `icon-192`, `icon-512`, `apple-touch-icon`, `site.webmanifest`). |

Manifest: `backend/app/views/pwa/manifest.json.erb`.  
Layout links: `backend/app/views/layouts/application.html.erb`.

## Rails UI logo

- `backend/app/assets/images/domino-chain-logo.png` — headers, auth, beta sidebar (`image_tag "domino-chain-logo.png"`).

## Android (`android/app/src/main/res/`)

| Resource | Use |
|-----------|-----|
| `mipmap-*/ic_launcher.png` + `ic_launcher_round.png` | Launcher assets raster par densité. |
| `mipmap-*/ic_launcher_foreground.png` | Foreground adaptive icon raster par densité. |
| `mipmap-anydpi-v26/ic_launcher.xml` | Déclaration adaptive icon (inclut monochrome). |
| `values/ic_launcher_background.xml` | Couleur de fond adaptive icon. |
| `drawable/ic_notification.xml` | Notification icon vector (source). |
| `drawable-*/ic_notification.png` | Fallbacks raster notification par densité. |

Staging no longer overrides the launcher foreground so dev/prod share the same Domino Chain artwork.

## Tiny sizes

- **Favicon / SVG**: simplified geometry, high contrast.
- **Notification**: filled “D” silhouette only (`ic_notification.xml`), no gradient.

## Naming

- Product name: **Domino Chain** (app label, PWA `name`, notification titles, default HTML `<title>`).
