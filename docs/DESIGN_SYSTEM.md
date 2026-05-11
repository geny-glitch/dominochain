# Domino Chain Design System

Design system unifié pour le web (Rails) et l'app Android. Inspiré de Blade Runner 2049 — sombre, atmosphérique, accent primary magenta + accents blue/violet.

---

## Couleurs

| Token | Hex | Usage |
|-------|-----|-------|
| `bg` | `#0a0a0b` | Fond principal |
| `surface` | `#121214` | Cartes, blocs |
| `surface-elevated` | `#1a1a1d` | Surfaces surélevées |
| `border` | `#2f2f34` | Bordures |
| `text` | `#f0eeea` | Texte principal |
| `text-muted` | `#b8b5b1` | Labels, texte secondaire |
| `text-dim` | `#8a8784` | Texte tertiaire |
| `magenta` | `#ec4899` | Primary / CTA |
| `magenta-dim` | `#db2777` | Hover primary |
| `blue` | `#22d3ee` | Liens, accents, focus |
| `blue-dim` | `#06b6d4` | Hover blue |
| `violet` | `#a855f7` | Secondary / premium |
| `violet-dim` | `#9333ea` | Hover secondary |
| `error` | `#ef6b6b` | Erreurs |
| `success` | `#22d3ee` | Succès (aligné accent blue) |

> Compatibilité : `amber` et `teal` restent disponibles comme alias legacy vers `magenta` et `blue`.

---

## Typographie

- **Font** : Inter (web), Roboto (Android)
- **Title** : 1.75rem / 28sp, weight 300, letter-spacing 0.08em
- **Subtitle** : 0.8rem / 13sp
- **Body** : 0.875rem / 14sp
- **Small** : 0.75rem / 12sp
- **Tiny** : 0.65rem / 11sp

---

## Espacement (dp / rem)

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

## Rayons

- **sm** : 4dp
- **md** : 6dp
- **lg** : 8dp

---

## Composants

### Boutons / CTA

| Variant | Usage |
|---------|-------|
| `primary` | Action principale (magenta) |
| `secondary` | Action secondaire (violet outline) |
| `ghost` | Liens, actions tertiaires (blue) |
| `sm` | Petit format |

### Formulaires

- **Form group** : `ds-form-group` — espacement entre champs
- **Label** : `ds-form-label` — small, text-muted
- **Input** : `ds-input` — fond bg, bordure border, focus teal
- **Textarea** : `ds-input ds-textarea`
- **Hint** : `ds-form-hint` — texte d'aide

### Sections

- **Section title** : `ds-section-title` — uppercase, letter-spacing, text-muted

### Flash / Feedback

- **Success** : fond accent translucide, bordure success
- **Error** : fond rouge translucide, bordure error

### Badges / Status / Toggles

- **Badge / status** : `ds-badge`, `ds-status` + variantes (`--on`, `--off`, `--pending`, `--error`, `--locked`, `--live`)
- **Toggle** : `ds-toggle` et variantes (`ds-toggle--on`) ou composants DS qui l’embarquent (`ds-beta-catalog-toggle-*`)
- **Règle** : conserver les variantes DS; ne pas restyler localement par page.

---

## Structure de page (web)

```erb
<div class="ds-page">
  <div class="ds-container">
    <header class="ds-header">...</header>
    <!-- contenu -->
  </div>
</div>
```

## Structure d'écran (Android)

- `ds_page` : layout racine avec padding
- `ds_section` : bloc avec espacement
- `ds_card` : carte avec surface, bordure, radius

## Logos / Favicons / App icons

- **Web favicons** : `backend/public/favicons/` (`favicon-16/32/48/64/96`, `icon-192`, `icon-512`, `apple-touch-icon`, `site.webmanifest`)
- **Web mark SVG** : `backend/public/icon.svg`
- **Android launcher** : `android/app/src/main/res/mipmap-*/ic_launcher*.png` + `mipmap-anydpi-v26/ic_launcher*.xml`
- **Android notification** : `android/app/src/main/res/drawable/ic_notification.xml` (+ fallback PNGs `drawable-*/ic_notification.png`)
- **Launcher background** : `android/app/src/main/res/values/ic_launcher_background.xml`

---

## Références

- **Web** : `backend/app/assets/stylesheets/design_system/`
- **Android** : `android/app/src/main/res/values/` (colors, themes, styles, dimens)
- **Brand assets** : `docs/BRAND_DOMINO_CHAIN.md`
