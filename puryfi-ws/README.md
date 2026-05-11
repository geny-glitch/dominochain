# BG PuryFi — WebSocket Plugin

WebSocket server (local or Fly.io): PuryFi connects to a **dedicated URL** `wss://…/ws/<your_token>`. The token comes from the **beta dashboard** (PuryFi section) and identifies your account.

The service calls the BG API: `GET /api/showcase_settings` (Bearer = URL token) and `POST /api/chaster/add_time`.

## Prerequisites

- Node 22+
- PuryFi ≥ 0.8.6 (beta), with **requestMediaProcesses** intent granted in the extension.

## Setup

```bash
cd puryfi-ws
npm install
npm run setup
```

`setup` only writes `BG_BACKEND_URL` to `.env`. On the **beta dashboard**, copy the displayed WebSocket URL (for example `wss://puryfi.dominochain.app/ws/…`) and paste it into PuryFi → Plugins → WebSocket. Seconds per label and minimum score are configured on the dashboard (persisted backend-side).

## Local

```bash
npm run dev
```

In PuryFi, use the dashboard URL (same format, using `ws://` if needed): `ws://localhost:8080/ws/<your_token>`.

## Fly.io

App: **`bg-puryfi-ws`** — HTTP origin: **https://puryfi.dominochain.app**; WebSocket on **`/ws/:token`**.

Required secret (without trailing slash):

```bash
fly secrets set BG_BACKEND_URL="https://dominochain.app" -a bg-puryfi-ws
```

Deploy from the repository root:

```bash
fly deploy -c fly.puryfi-ws.toml --remote-only
```

(CI : voir `.github/workflows/puryfi-ws.yml`.)
