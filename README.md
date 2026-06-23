# Domino Chain — Own their backgrounds

Android app + Rails backend. Register your device, upload an image via the web, and it becomes your wallpaper.

**Backend:** https://dominochain.app

## Structure

```
bg/
├── android/     # Kotlin Android app
├── backend/    # Rails 7 API + web upload UI
├── puryfi-ws/  # PuryFi WebSocket bridge → BG API (Fly.io)
├── docs/       # GitHub Pages (optional static site)
└── README.md
```

## Run the Android app locally (Mac + Android Studio)

### 1. Prerequisites

- Android Studio installed
- JDK 17 (bundled with Android Studio)
- Android emulator or physical device

### 2. Open the project

1. Launch Android Studio
2. **File → Open** → select the `bg/android` folder
3. Wait for Gradle sync to finish (progress bar at the bottom)

### 3. Configure `local.properties`

1. If `android/local.properties` does not exist: **File → New → File** → name it `local.properties`
2. Android Studio often creates this file automatically. In that case, just edit it.
3. Add or verify:

```properties
sdk.dir=/Users/TON_USERNAME/Library/Android/sdk
API_BASE_URL_PROD=https://dominochain.app
API_BASE_URL_STAGING=https://beta.dominochain.app
```

To find `sdk.dir`: **Android Studio → Settings → Appearance & Behavior → System Settings → Android SDK** → the path is shown at the top.

### 4. Start an emulator or connect a device

**Emulator:**
1. **Tools → Device Manager** (or the phone icon in the toolbar)
2. Create a device if needed (for example Pixel 6, API 34)
3. Click ▶ to start the emulator

**Physical device:**
1. Enable developer mode: **Settings → About phone** → tap "Build number" 7 times
2. Enable USB debugging: **Settings → Developer options → USB debugging**
3. Connect the phone over USB
4. Accept the authorization prompt on the phone

### 5. Run the app

1. Select your device/emulator in the device selector
2. Click ▶ **Run** (or `Ctrl+R` / `Cmd+R`)
3. The app installs and starts

### 6. Configure Firebase (for push notifications)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a project (or use an existing one)
3. **Add an Android app**: package name `com.bg`
4. Download `google-services.json` and replace `android/app/google-services.json`
5. (Optional) For backend usage: Project Settings → Service accounts → Generate new private key → save the JSON

### 7. Test the flow

1. The app shows a link (for example `https://dominochain.app/w/xxx`)
2. Click it or copy it into a browser
3. Open the page on your phone or Mac
4. Upload an image
5. The app updates the wallpaper **immediately** (push) or on next poll/app launch

---

## Local backend (optional)

If you want to use a local Rails backend:

```bash
cd backend
bundle install
bin/rails db:create db:migrate
bin/rails server
```

Then in `local.properties`:
- Emulator: `API_BASE_URL_PROD=http://10.0.2.2:3000`
- Physical device: `API_BASE_URL_PROD=http://YOUR_MAC_IP:3000` (find your IP with `ifconfig | grep "inet "`)
- For the Android staging flavor: `API_BASE_URL_STAGING=http://10.0.2.2:3000` (or your Fly staging backend)

## Deploy (Fly.io)

1. Create Postgres: `fly postgres create` (or attach existing)
2. Create volume: `fly volumes create storage_volume --size 1 --region <region>`
3. Set secrets: `fly secrets set RAILS_MASTER_KEY=$(cat backend/config/master.key)`
4. Set DATABASE_URL from Postgres connection string
5. For FCM push: `fly secrets set FIREBASE_PROJECT_ID=your-project-id FIREBASE_CREDENTIALS_JSON="$(cat path/to/service-account.json)"`
6. Deploy: `cd backend && fly deploy`

## Staging (Fly + Android)

- Staging Fly backend file: `backend/fly.staging.toml` (app `bg-backend-staging`)
- Staging backend pipeline: push to `staging` branch (workflow `fly-deploy.yml`)
- Staging Android APK: `staging` flavor, package `com.bg.staging`, installable next to production
- Staging Android pipeline: push to `staging` branch (workflow `android-ota-release.yml`)
- Required GitHub secret to notify staging backend: `DEPLOY_SECRET_STAGING`
- Add a Firebase Android app `com.bg.staging` and place its `google-services.json` (or equivalent flavor config)
- The site exposes an APK download link: `/android/app.apk` (so `https://beta.dominochain.app/android/app.apk` in staging)

### Home page (creator collage)

The home page displays a collage of DB-stored images. Configure the list in Admin > Settings (one name per line), then run:

```bash
cd backend && bin/rails wikimedia:fetch_images
```

Or save the list in admin: images are fetched automatically (10 per profile).
