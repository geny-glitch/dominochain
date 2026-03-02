# Bg — Wallpaper Sync

Android app + Rails backend. Register your device, upload an image via the web, and it becomes your wallpaper.

## Structure

```
bg/
├── android/     # Kotlin Android app
├── backend/    # Rails 7 API + web upload UI
└── README.md
```

## Backend (Rails)

```bash
cd backend
bundle install
bin/rails db:create db:migrate
bin/rails server
```

Runs at http://localhost:3000. For Android emulator, use `http://10.0.2.2:3000` as the API base URL.

### API

- `POST /api/devices` — Register device. Body: `{ "device_id": "uuid" }`
- `GET /api/devices/:id/wallpaper` — Get current wallpaper URL
- `GET /w/:device_id` — Web upload form

## Android

1. Copy `android/local.properties.example` to `android/local.properties`
2. Set `sdk.dir` to your Android SDK path
3. Optionally set `API_BASE_URL` (default: `http://10.0.2.2:3000` for emulator)
4. Open in Android Studio or run `./gradlew assembleDebug`

## Deploy (Fly.io)

1. Create Postgres: `fly postgres create` (or attach existing)
2. Create volume: `fly volumes create storage_volume --size 1 --region <region>`
3. Set secrets: `fly secrets set RAILS_MASTER_KEY=$(cat backend/config/master.key)`
4. Set DATABASE_URL from Postgres connection string
5. Deploy: `cd backend && fly deploy`

Update Android `local.properties` with `API_BASE_URL=https://<app-name>.fly.dev`
