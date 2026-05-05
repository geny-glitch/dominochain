# BG PuryFi — plugin WebSocket

Serveur WebSocket (local ou Fly.io) : PuryFi s’y connecte sur une **URL dédiée** `wss://…/ws/<ton_token>`. Le token provient du **dashboard beta** (section PuryFi) et identifie ton compte.

Le service appelle l’API BG : `GET /api/showcase_settings` (Bearer = token d’URL) et `POST /api/chaster/add_time`.

## Prérequis

- Node 22+
- PuryFi ≥ 0.8.6 (beta), intent **requestMediaProcesses** accordé dans l’extension.

## Setup

```bash
cd puryfi-ws
npm install
npm run setup
```

`setup` n’écrit que `BG_BACKEND_URL` dans `.env`. Sur le **dashboard beta**, copie l’URL WebSocket affichée (ex. `wss://bg-puryfi-ws.fly.dev/ws/…`) et colle-la dans PuryFi → Plugins → WebSocket. Les secondes par label et le score minimum se règlent sur le dashboard (enregistrés côté backend).

## Local

```bash
npm run dev
```

Dans PuryFi, utilise l’URL du dashboard (même forme, en `ws://` si besoin) : `ws://localhost:8080/ws/<ton_token>`.

## Fly.io

App : **`bg-puryfi-ws`** — origin HTTP : **https://bg-puryfi-ws.fly.dev** ; WebSocket sur **`/ws/:token`**.

Secret obligatoire (sans slash final) :

```bash
fly secrets set BG_BACKEND_URL="https://bg-backend.fly.dev" -a bg-puryfi-ws
```

Déploiement depuis la racine du dépôt :

```bash
fly deploy -c fly.puryfi-ws.toml --remote-only
```

(CI : voir `.github/workflows/puryfi-ws.yml`.)
