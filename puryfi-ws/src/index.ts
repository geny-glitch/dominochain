import "dotenv/config";
import http from "node:http";
import { WebSocketServer as WsSocketServer } from "ws";
import {
  WebSocketConnection,
  type WebSocketConnection as WebSocketConnectionType,
} from "@pury-fi/plugin-sdk/websocket";
import { bgAddTime, bgGetShowcaseSettings } from "../shared/bg-api.js";
import { analyzeScan, defaultSecondsPerLabel } from "../shared/puryfi-detect.js";
import type { PluginConfigShape } from "../shared/puryfi-detect.js";

function mergeRemoteConfig(remote: {
  puryfi_min_score?: number;
  puryfi_seconds_per_label?: Record<string, number>;
}): PluginConfigShape {
  const secondsPerLabel = defaultSecondsPerLabel();
  const raw = remote.puryfi_seconds_per_label ?? {};
  for (const [k, v] of Object.entries(raw)) {
    if (k in secondsPerLabel && typeof v === "number") {
      secondsPerLabel[k] = Math.max(0, Math.floor(v));
    }
  }
  return {
    minScore:
      typeof remote.puryfi_min_score === "number"
        ? remote.puryfi_min_score
        : 0.5,
    secondsPerLabel,
  };
}

async function fetchConfig(
  baseUrl: string,
  pluginToken: string,
  fallback: PluginConfigShape,
): Promise<PluginConfigShape> {
  const res = await bgGetShowcaseSettings(baseUrl, pluginToken);
  if (!res.ok) {
    console.warn("showcase_settings:", res.error);
    return fallback;
  }
  return mergeRemoteConfig(res.settings);
}

async function ensureIntents(connection: WebSocketConnectionType) {
  const desired = ["requestMediaProcesses"] as const;

  const grantedRes = await connection.sendMessage("getPluginIntents", {});
  if (grantedRes.type === "error") {
    throw new Error(grantedRes.message);
  }
  let granted = grantedRes.intents;

  if (!desired.every((i) => granted.includes(i))) {
    await connection.sendMessage("requestPluginIntents", {
      intents: [...desired],
    });
    await new Promise<void>((resolve, reject) => {
      const t = setTimeout(
        () => reject(new Error("Timeout attente intents PuryFi")),
        120_000,
      );
      connection.on("message", "intentsGrant", function listener({ intents }) {
        granted = intents;
        if (desired.every((i) => granted.includes(i))) {
          clearTimeout(t);
          connection.off("message", "intentsGrant", listener);
          resolve();
        }
      });
    });
  }
}

async function runPuryFiConnection(
  connection: WebSocketConnectionType,
  pluginToken: string,
) {
  const baseUrl = process.env.BG_BACKEND_URL;
  if (!baseUrl) {
    throw new Error("Manque BG_BACKEND_URL dans l'environnement");
  }

  let config = await fetchConfig(
    baseUrl,
    pluginToken,
    mergeRemoteConfig({}),
  );
  setInterval(() => {
    fetchConfig(baseUrl, pluginToken, config)
      .then((c) => {
        config = c;
      })
      .catch(() => {
        /* garde la config précédente */
      });
  }, 10_000);

  await new Promise<void>((resolve, reject) => {
    const t = setTimeout(
      () => reject(new Error("Timeout attente open PuryFi")),
      30_000,
    );
    connection.once("open", () => {
      clearTimeout(t);
      resolve();
    });
    connection.once("error", (e) => {
      clearTimeout(t);
      reject(e);
    });
  });

  await new Promise<void>((resolve, reject) => {
    connection.once("message", "ready", (payload) => {
      const res = connection.handleReadyMessage(payload);
      if (res.type === "ok") resolve();
      else
        reject(
          new Error(
            "type" in res && "message" in res
              ? String((res as { message?: string }).message)
              : "Handshake PuryFi refusé",
          ),
        );
      return res;
    });
  });

  await connection.sendMessage("setPluginManifest", {
    manifest: {
      name: "BG PuryFi WebSocket",
      version: "1.0.0",
      description: "Ajoute du temps Chaster selon les détections PuryFi",
      author: null,
      website: null,
    },
  });

  await ensureIntents(connection);

  const sub = await connection.sendMessage("subscribeToStaticMediaScans", {});
  if (sub.type === "error") {
    throw new Error(sub.message);
  }

  connection.on("message", "staticMediaScan", async (payload) => {
    const { objects } = payload;
    const result = analyzeScan(
      objects.map((o) => ({ label: o.label, score: o.score })),
      config,
    );

    if (result.matched.length === 0) return;

    const ts = new Date().toISOString();
    console.log(
      `[${ts}] staticMediaScan → total ${result.totalSeconds}s | ${result.summaryLine}`,
    );

    const api = await bgAddTime(baseUrl, pluginToken, result.totalSeconds);
    if (!api.ok) {
      console.error(`[${ts}] API add_time échec:`, api.error);
    } else {
      console.log(
        `[${ts}] API OK added_seconds=${api.added_seconds ?? result.totalSeconds}`,
      );
    }
  });

  console.log("BG PuryFi WebSocket prêt — en écoute des scans média.");
}

function main() {
  const port = Number(process.env.PORT) || 8080;
  const httpServer = http.createServer((req, res) => {
    const u = new URL(req.url || "/", `http://${req.headers.host || "127.0.0.1"}`);
    if (req.method === "GET" && u.pathname === "/") {
      res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("BG PuryFi WS OK\n");
      return;
    }
    res.writeHead(404);
    res.end();
  });

  const wss = new WsSocketServer({ noServer: true });

  httpServer.on("upgrade", (request, socket, head) => {
    const u = new URL(request.url || "/", `http://${request.headers.host || "127.0.0.1"}`);
    const m = u.pathname.match(/^\/ws\/([^/]+)\/?$/);
    if (!m) {
      socket.destroy();
      return;
    }
    const pluginToken = decodeURIComponent(m[1]);
    wss.handleUpgrade(request, socket, head, (ws) => {
      const connection = new WebSocketConnection(ws);
      connection.open();
      console.log("Client PuryFi connecté");
      runPuryFiConnection(connection, pluginToken).catch((err) => {
        console.error("Erreur connexion PuryFi:", err);
      });
    });
  });

  httpServer.on("error", (err) => {
    console.error("Serveur HTTP:", err);
  });

  wss.on("error", (err) => {
    console.error("WebSocket upgrade:", err);
  });

  httpServer.listen(port, () => {
    console.log(`HTTP + WebSocket /ws/:token sur le port ${port}`);
  });
}

main();
