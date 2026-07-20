import "dotenv/config";
import http from "node:http";
import util from "node:util";
import { WebSocketServer as WsSocketServer } from "ws";
import {
  WebSocketConnection,
  type PluginConfiguration,
  type WebSocketConnection as WebSocketConnectionType,
} from "@pury-fi/plugin-sdk/websocket";
import { bgAddTime, bgGetShowcaseSettings, bgPishockShock } from "../shared/bg-api.js";
import {
  analyzeScan,
  defaultPishockLevelSettings,
  defaultSecondsPerLabel,
  defaultShockLevelPerLabel,
} from "../shared/puryfi-detect.js";
import type { PluginConfigShape } from "../shared/puryfi-detect.js";
import {
  logStaticMediaScanDebug,
  parseDedupeWindowMs,
  puryfiLogPluginPayload,
  StaticScanDedupeLogState,
} from "../shared/puryfi-scan-debug.js";

/** Ce que PuryFi renvoie avec getPluginConfiguration — uniquement ce déposé via setPluginConfiguration (pas la config censure PuryFi). */
function secondsPerLabelPreview(
  secondsPerLabel: PluginConfigShape["secondsPerLabel"],
  maxPairs = 24,
): string {
  const parts: string[] = [];
  for (const [id, sec] of Object.entries(secondsPerLabel)) {
    if (typeof sec !== "number" || sec <= 0) continue;
    parts.push(`${id}:${sec}s`);
    if (parts.length >= maxPairs) {
      parts.push("…");
      break;
    }
  }
  return parts.length ? parts.join(", ") : "(aucune seconde > 0)";
}

function pluginUiConfigurationFromMerged(
  merged: PluginConfigShape,
): PluginConfiguration {
  if (!puryfiLogPluginPayload()) {
    return {};
  }
  return {
    bg_doc: {
      name: "Pont BG — où régler les secondes / score min",
      type: "string",
      value:
        "Dashboard beta → PuryFi. Snapshot pour le debug serveur ; pas la config générale de l’extension.",
    },
    bg_min_score: {
      name: "(debug) Score min utilisé par le pont (snapshot)",
      type: "number",
      value: merged.minScore,
    },
    bg_seconds_preview: {
      name: "(debug) Secondes par label > 0 (snapshot)",
      type: "string",
      value: secondsPerLabelPreview(merged.secondsPerLabel),
    },
  };
}

async function pushPluginUiConfiguration(
  connection: WebSocketConnectionType,
  merged: PluginConfigShape,
): Promise<void> {
  const res = await connection.sendMessage("setPluginConfiguration", {
    configuration: pluginUiConfigurationFromMerged(merged),
  });
  if (res.type === "error") {
    console.warn("setPluginConfiguration:", res.message);
  }
}

function mergeRemoteConfig(remote: {
  puryfi_min_score?: number;
  puryfi_seconds_per_label?: Record<string, number>;
  puryfi_shock_level_per_label?: Record<string, number>;
  puryfi_pishock_level_settings?: Record<string, { intensity: number; duration: number }>;
}): PluginConfigShape {
  const secondsPerLabel = defaultSecondsPerLabel();
  const raw = remote.puryfi_seconds_per_label ?? {};
  for (const [k, v] of Object.entries(raw)) {
    if (k in secondsPerLabel && typeof v === "number") {
      secondsPerLabel[k] = Math.max(0, Math.floor(v));
    }
  }

  const shockLevelPerLabel = defaultShockLevelPerLabel();
  const shockRaw = remote.puryfi_shock_level_per_label ?? {};
  for (const [k, v] of Object.entries(shockRaw)) {
    if (k in shockLevelPerLabel && typeof v === "number") {
      shockLevelPerLabel[k] = Math.max(0, Math.min(3, Math.floor(v)));
    }
  }

  const pishockLevelSettings = defaultPishockLevelSettings();
  const levelRaw = remote.puryfi_pishock_level_settings ?? {};
  for (const level of ["1", "2", "3"] as const) {
    const entry = levelRaw[level];
    if (!entry || typeof entry !== "object") continue;
    if (typeof entry.intensity === "number") {
      pishockLevelSettings[level].intensity = Math.max(1, Math.min(100, Math.floor(entry.intensity)));
    }
    if (typeof entry.duration === "number") {
      pishockLevelSettings[level].duration = Math.max(1, Math.min(15, Math.floor(entry.duration)));
    }
  }

  return {
    minScore:
      typeof remote.puryfi_min_score === "number"
        ? remote.puryfi_min_score
        : 0.5,
    secondsPerLabel,
    shockLevelPerLabel,
    pishockLevelSettings,
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
  const desired = ["readMediaProcesses", "requestMediaProcesses"] as const;

  await new Promise<void>((resolve, reject) => {
    let finished = false;
    const t = setTimeout(() => {
      finish(() => reject(new Error("Timeout attente intents PuryFi")));
    }, 120_000);

    const finish = (fn: () => void) => {
      if (finished) return;
      finished = true;
      clearTimeout(t);
      connection.off("message", "intentsGrant", onGrant);
      fn();
    };

    const check = (): void => {
      void connection
        .sendMessage("getPluginIntents", {})
        .then((res) => {
          if (res.type === "error") {
            finish(() => reject(new Error(res.message)));
            return;
          }
          if (desired.every((i) => res.intents.includes(i))) {
            finish(() => resolve());
          }
        })
        .catch((e) => {
          finish(() =>
            reject(e instanceof Error ? e : new Error(String(e))),
          );
        });
    };

    function onGrant() {
      check();
    }

    connection.on("message", "intentsGrant", onGrant);

    void connection
      .sendMessage("requestPluginIntents", { intents: [...desired] })
      .then((req) => {
        if (req.type === "error") {
          finish(() => reject(new Error(req.message)));
          return;
        }
        check();
      })
      .catch((e) => {
        finish(() =>
          reject(e instanceof Error ? e : new Error(String(e))),
        );
      });
  });
}

async function logGetPluginConfigurationDebug(
  connection: WebSocketConnectionType,
): Promise<void> {
  const ts = new Date().toISOString();
  try {
    const res = await connection.sendMessage("getPluginConfiguration", {});
    if (res.type === "error") {
      console.warn(
        `[${ts}] [PuryFi DEBUG] getPluginConfiguration error:`,
        res.message,
      );
      return;
    }
    if (res.configuration == null) {
      console.log(
        `[${ts}] [PuryFi DEBUG] getPluginConfiguration → configuration=${util.inspect(res.configuration, { colors: false })} (réponse SDK complète: ${util.inspect(res, { depth: 4, colors: false })})\n`,
        `[${ts}] [PuryFi DEBUG] ↑ « plugin configuration » = champs que TON plugin déclare (setPluginConfiguration), pas les réglages généraux PuryFi. null si l’extension n’a encore rien stocké.`,
      );
      return;
    }
    if (
      Object.keys(res.configuration).length === 0 &&
      puryfiLogPluginPayload()
    ) {
      console.warn(
        `[${ts}] [PuryFi DEBUG] getPluginConfiguration encore {} alors que DEBUG est actif — setPluginConfiguration a peut‑être été refusé, ou reconnecte / redéploie le pont.`,
      );
    }
    console.log(
      `[${ts}] [PuryFi DEBUG] getPluginConfiguration:\n${util.inspect(res.configuration, { depth: 8, colors: false })}`,
    );
  } catch (e) {
    console.warn(`[${ts}] [PuryFi DEBUG] getPluginConfiguration:`, e);
  }
}

async function runPuryFiConnection(
  connection: WebSocketConnectionType,
  pluginToken: string,
) {
  if (puryfiLogPluginPayload()) {
    connection.setDebug(true);
    console.log(
      "[PuryFi DEBUG] PURYFI_LOG_PLUGIN_PAYLOAD activé — journalisation étendue (SDK + staticMediaScan).",
    );
  }

  const scanDedupeLog = puryfiLogPluginPayload()
    ? new StaticScanDedupeLogState()
    : null;
  const dedupeWindowMs = parseDedupeWindowMs();

  const baseUrl = process.env.BG_BACKEND_URL;
  if (!baseUrl) {
    throw new Error("Manque BG_BACKEND_URL dans l'environnement");
  }

  // open() émet « open » tout de suite : enregistrer les listeners avant de l’appeler.
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
    connection.open();
  });

  // Le client envoie « ready » très tôt : même problème que pour open() si on
  // attend fetchConfig avant d’écouter.
  const readyPromise = new Promise<void>((resolve, reject) => {
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

  let config = mergeRemoteConfig({});
  const configPromise = fetchConfig(
    baseUrl,
    pluginToken,
    config,
  ).then((c) => {
    config = c;
  });

  await Promise.all([readyPromise, configPromise]);

  setInterval(() => {
    fetchConfig(baseUrl, pluginToken, config)
      .then((c) => {
        config = c;
        if (puryfiLogPluginPayload()) {
          void pushPluginUiConfiguration(connection, config);
        }
      })
      .catch(() => {
        /* garde la config précédente */
      });
  }, 10_000);

  await connection.sendMessage("setPluginManifest", {
    manifest: {
      name: "Domino Chain PuryFi WebSocket",
      version: "1.0.0",
      description: "Adds Chaster time based on PuryFi detections",
      author: null,
      website: null,
    },
  });

  // Schéma côté PuryFi : {} en prod ; en PURYFI_LOG_PLUGIN_PAYLOAD, snapshot dashboard pour que getPluginConfiguration ne soit pas vide.
  await pushPluginUiConfiguration(connection, config);

  await ensureIntents(connection);

  const sub = await connection.sendMessage("subscribeToStaticMediaScans", {});
  if (sub.type === "error") {
    throw new Error(sub.message);
  }

  if (puryfiLogPluginPayload()) {
    await logGetPluginConfigurationDebug(connection);
    const pluginConfigLogInterval = setInterval(() => {
      void logGetPluginConfigurationDebug(connection);
    }, 60_000);
    connection.once("close", () => {
      clearInterval(pluginConfigLogInterval);
    });
  }

  connection.on("message", "staticMediaScan", async (payload) => {
    if (puryfiLogPluginPayload() && scanDedupeLog) {
      logStaticMediaScanDebug(payload, scanDedupeLog, dedupeWindowMs);
    }

    const { objects } = payload;
    const result = analyzeScan(
      objects.map((o) => ({ label: o.label, score: o.score })),
      config,
    );

    if (result.totalSeconds < 1 && !result.shock) return;

    const ts = new Date().toISOString();
    const shockLine = result.shock
      ? ` | PiShock L${result.shock.level} ${result.shock.intensity}/${result.shock.duration}s`
      : "";
    console.log(
      `[${ts}] staticMediaScan → total ${result.totalSeconds}s | ${result.summaryLine}${shockLine}`,
    );

    if (result.totalSeconds >= 1) {
      const api = await bgAddTime(baseUrl, pluginToken, result.totalSeconds);
      if (!api.ok) {
        console.error(`[${ts}] API add_time échec:`, api.error);
      } else {
        console.log(
          `[${ts}] API OK added_seconds=${api.added_seconds ?? result.totalSeconds}`,
        );
      }
    }

    if (result.shock) {
      const shockApi = await bgPishockShock(
        baseUrl,
        pluginToken,
        result.shock.intensity,
        result.shock.duration,
      );
      if (!shockApi.ok) {
        console.error(`[${ts}] API pishock échec:`, shockApi.error);
      } else {
        console.log(
          `[${ts}] PiShock OK level=${result.shock.level} intensity=${result.shock.intensity} duration=${result.shock.duration}`,
        );
      }
    }
  });

  console.log("Domino Chain PuryFi WebSocket ready — listening for media scans.");
}

function main() {
  const port = Number(process.env.PORT) || 8080;
  const httpServer = http.createServer((req, res) => {
    const u = new URL(req.url || "/", `http://${req.headers.host || "127.0.0.1"}`);
    if (req.method === "GET" && u.pathname === "/") {
      res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("Domino Chain PuryFi WS OK\n");
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
