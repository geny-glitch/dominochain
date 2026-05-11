# Domino Chain Design System

Design system unifié pour le web (Rails) et l'app Android. Inspiré de Blade Runner 2049 — sombre, atmosphérique, accents ambre et teal.

---

## Couleurs

| Token | Hex | Usage |
|-------|-----|-------|
| `bg` | `#0a0a0b` | Fond principal |
| `surface` | `#121214` | Cartes, blocs |
| `surface-elevated` | `#1a1a1d` | Surfaces surélevées |
| `border` | `#2a2a2e` | Bordures |
| `text` | `#e8e6e3` | Texte principal |
| `text-muted` | `#8a8784` | Labels, texte secondaire |
| `amber` | `#e9a03f` | Primary / CTA |
| `amber-dim` | `#b87d2e` | Hover primary |
| `teal` | `#2ec4b6` | Liens, accents |
| `teal-dim` | `#1e9d92` | Hover teal |
| `error` | `#c75c5c` | Erreurs |
| `success` | `#4a9d7a` | Succès |

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

### Boutons

| Variant | Usage |
|---------|-------|
| `primary` | Action principale (amber) |
| `secondary` | Action secondaire (surface-elevated) |
| `ghost` | Liens, actions tertiaires (teal) |
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

- **Success** : fond vert translucide, bordure success
- **Error** : fond rouge translucide, bordure error

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

---

## Références

- **Web** : `backend/app/assets/stylesheets/design_system/`
- **Android** : `android/app/src/main/res/values/` (colors, themes, styles, dimens)
