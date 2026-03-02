# OTB — Own their backgrounds

Android app + Rails backend. Register your device, upload an image via the web, and it becomes your wallpaper.

**Backend:** https://bg-backend.fly.dev

## Structure

```
bg/
├── android/     # Kotlin Android app
├── backend/    # Rails 7 API + web upload UI
└── README.md
```

## Lancer l'app Android en local (Mac + Android Studio)

### 1. Prérequis

- Android Studio installé
- JDK 17 (fourni par Android Studio)
- Émulateur Android ou appareil physique

### 2. Ouvrir le projet

1. Lance Android Studio
2. **File → Open** → sélectionne le dossier `bg/android`
3. Attends que Gradle sync termine (barre de progression en bas)

### 3. Configurer local.properties

1. Si le fichier `android/local.properties` n’existe pas : **File → New → File** → nomme-le `local.properties`
2. Android Studio crée souvent ce fichier automatiquement. Dans ce cas, édite-le.
3. Ajoute ou vérifie :

```properties
sdk.dir=/Users/TON_USERNAME/Library/Android/sdk
API_BASE_URL=https://bg-backend.fly.dev
```

Pour trouver `sdk.dir` : **Android Studio → Settings → Appearance & Behavior → System Settings → Android SDK** → le chemin est affiché en haut.

### 4. Lancer l’émulateur ou connecter un appareil

**Émulateur :**
1. **Tools → Device Manager** (ou icône téléphone dans la barre)
2. Crée un device si besoin (ex. Pixel 6, API 34)
3. Clique sur ▶ pour lancer l’émulateur

**Appareil physique :**
1. Active le mode développeur : **Paramètres → À propos du téléphone** → appuie 7 fois sur « Numéro de build »
2. Active le débogage USB : **Paramètres → Options pour les développeurs → Débogage USB**
3. Connecte le téléphone en USB
4. Accepte l’autorisation sur le téléphone

### 5. Lancer l’app

1. Sélectionne ton appareil/émulateur dans la barre de sélection
2. Clique sur ▶ **Run** (ou `Ctrl+R` / `Cmd+R`)
3. L’app s’installe et se lance

### 6. Configurer Firebase (pour les push notifications)

1. Va sur [Firebase Console](https://console.firebase.google.com/)
2. Crée un projet (ou utilise un existant)
3. **Ajoute une app Android** : package name `com.bg`
4. Télécharge `google-services.json` et remplace `android/app/google-services.json`
5. (Optionnel) Pour le backend : Project Settings → Service accounts → Generate new private key → enregistre le JSON

### 7. Tester le flux

1. L’app affiche un lien (ex. `https://bg-backend.fly.dev/w/xxx`)
2. Clique dessus ou copie-le dans un navigateur
3. Ouvre la page sur ton téléphone ou ton Mac
4. Envoie une image
5. L’app met à jour le fond d’écran **immédiatement** (push) ou au prochain polling/lancement

---

## Backend local (optionnel)

Si tu veux utiliser un backend Rails local :

```bash
cd backend
bundle install
bin/rails db:create db:migrate
bin/rails server
```

Puis dans `local.properties` :
- Émulateur : `API_BASE_URL=http://10.0.2.2:3000`
- Appareil physique : `API_BASE_URL=http://TON_IP_MAC:3000` (trouve ton IP avec `ifconfig | grep "inet "`)

## Deploy (Fly.io)

1. Create Postgres: `fly postgres create` (or attach existing)
2. Create volume: `fly volumes create storage_volume --size 1 --region <region>`
3. Set secrets: `fly secrets set RAILS_MASTER_KEY=$(cat backend/config/master.key)`
4. Set DATABASE_URL from Postgres connection string
5. Pour les push FCM : `fly secrets set FIREBASE_PROJECT_ID=ton-project-id FIREBASE_CREDENTIALS_JSON="$(cat path/to/service-account.json)"`
6. Deploy: `cd backend && fly deploy`
