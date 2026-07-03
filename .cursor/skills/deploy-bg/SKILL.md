---
name: deploy-bg
description: Deploys the BG project (backend on Fly.io, Android app on connected phone). Use when the user asks to deploy, push to production, or install the app on their phone.
---

# Deploy BG

## Backend (Fly.io)

Production:

```bash
cd backend && fly deploy
```

Staging:

```bash
cd backend && fly deploy --config fly.staging.toml
```

- Production app: `dc-backend` (`backend/fly.toml`)
- Staging app: `dc-backend-staging` (`backend/fly.staging.toml`)
- Processes: `app` (Puma HTTP) + `worker` (`bin/jobs` / Solid Queue)
- Files: Tigris object storage (`dc-shared` bucket, env prefix `production/` or `staging/`)

### Storage migration (local Fly volume → Tigris)

One-time per environment if blobs still live on a mounted volume:

```bash
fly ssh console -a dc-backend-staging -C "sh -c 'DRY_RUN=1 bin/rails storage:migrate_to_tigris'"
fly ssh console -a dc-backend-staging -C "bin/rails storage:migrate_to_tigris"
```

If Fly warns about removing a volume mount, destroy the old app machine and redeploy with `-y`:

```bash
fly machine destroy <app-machine-id> -a dc-backend-staging --force
fly deploy --config fly.staging.toml -y --now
```

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
