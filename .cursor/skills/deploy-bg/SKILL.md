---
name: deploy-bg
description: Deploys the BG project (backend on Fly.io, Android app on connected phone). Use when the user asks to deploy, push to production, or install the app on their phone.
---

# Deploy BG

## Backend (Fly.io)

```bash
cd backend && fly deploy
```

- App: `bg-backend` (fly.toml)
- URL: https://bg-backend.fly.dev

## Android (téléphone)

```bash
cd android && ./gradlew installDebug
```

**Prérequis :**
- Téléphone connecté en USB avec débogage USB activé
- Ou débogage sans fil configuré (Android 11+)

**Alternative** : build l’APK sans installer :
```bash
cd android && ./gradlew assembleDebug
# APK généré dans android/app/build/outputs/apk/debug/app-debug.apk
```

## Déploiement complet

```bash
cd backend && fly deploy && cd ../android && ./gradlew installDebug
```
