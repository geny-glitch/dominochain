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

## Android (phone)

```bash
cd android && ./gradlew installDebug
```

**Prerequisites:**
- Phone connected over USB with USB debugging enabled
- Or wireless debugging configured (Android 11+)

**Alternative**: build the APK without installing:
```bash
cd android && ./gradlew assembleDebug
# APK generated at android/app/build/outputs/apk/debug/app-debug.apk
```

## Full Deployment

```bash
cd backend && fly deploy && cd ../android && ./gradlew installDebug
```
