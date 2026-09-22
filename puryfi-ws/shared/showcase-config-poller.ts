import { bgGetShowcaseSettings } from "./bg-api.js";
import type { PluginConfigShape } from "./puryfi-detect.js";

export const SHOWCASE_POLL_MS = 30_000;
export const SHOWCASE_MIN_REFETCH_MS = 10_000;
export const SHOWCASE_BACKOFF_MAX_MS = 5 * 60_000;
export const SHOWCASE_IDLE_CACHE_MS = 2 * 60_000;

type MergeFn = (remote: {
  puryfi_min_score?: number;
  puryfi_seconds_per_label?: Record<string, number>;
  puryfi_shock_level_per_label?: Record<string, number>;
  puryfi_pishock_level_settings?: Record<string, { intensity: number; duration: number }>;
}) => PluginConfigShape;

type ShowcasePoller = {
  token: string;
  baseUrl: string;
  mergeRemoteConfig: MergeFn;
  config: PluginConfigShape;
  refs: number;
  lastOkAt: number;
  lastAttemptAt: number;
  backoffMs: number;
  inFlight: Promise<PluginConfigShape> | null;
  timer: ReturnType<typeof setTimeout> | null;
  idleTimer: ReturnType<typeof setTimeout> | null;
};

const pollers = new Map<string, ShowcasePoller>();

function clearTimer(poller: ShowcasePoller): void {
  if (poller.timer) {
    clearTimeout(poller.timer);
    poller.timer = null;
  }
}

function clearIdleTimer(poller: ShowcasePoller): void {
  if (poller.idleTimer) {
    clearTimeout(poller.idleTimer);
    poller.idleTimer = null;
  }
}

function schedule(poller: ShowcasePoller, delayMs: number): void {
  clearTimer(poller);
  if (poller.refs <= 0) return;
  poller.timer = setTimeout(() => {
    void refresh(poller, false).finally(() => {
      schedule(poller, poller.backoffMs);
    });
  }, delayMs);
}

async function refresh(
  poller: ShowcasePoller,
  force: boolean,
): Promise<PluginConfigShape> {
  const now = Date.now();
  const recentlyOk =
    poller.lastOkAt > 0 && now - poller.lastOkAt < SHOWCASE_MIN_REFETCH_MS;
  if (!force && recentlyOk) {
    return poller.config;
  }
  if (poller.inFlight) {
    return poller.inFlight;
  }

  poller.lastAttemptAt = now;
  poller.inFlight = (async () => {
    try {
      const res = await bgGetShowcaseSettings(poller.baseUrl, poller.token);
      if (!res.ok) {
        console.warn("showcase_settings:", res.error);
        poller.backoffMs = Math.min(
          poller.backoffMs * 2,
          SHOWCASE_BACKOFF_MAX_MS,
        );
        return poller.config;
      }
      poller.config = poller.mergeRemoteConfig(res.settings);
      poller.lastOkAt = Date.now();
      poller.backoffMs = SHOWCASE_POLL_MS;
      return poller.config;
    } catch (err) {
      console.warn("showcase_settings:", err);
      poller.backoffMs = Math.min(
        Math.max(poller.backoffMs, SHOWCASE_POLL_MS) * 2,
        SHOWCASE_BACKOFF_MAX_MS,
      );
      return poller.config;
    } finally {
      poller.inFlight = null;
    }
  })();

  return poller.inFlight;
}

export async function acquireShowcaseConfig(opts: {
  baseUrl: string;
  pluginToken: string;
  mergeRemoteConfig: MergeFn;
}): Promise<{ config: () => PluginConfigShape; release: () => void }> {
  let poller = pollers.get(opts.pluginToken);
  if (!poller) {
    poller = {
      token: opts.pluginToken,
      baseUrl: opts.baseUrl,
      mergeRemoteConfig: opts.mergeRemoteConfig,
      config: opts.mergeRemoteConfig({}),
      refs: 0,
      lastOkAt: 0,
      lastAttemptAt: 0,
      backoffMs: SHOWCASE_POLL_MS,
      inFlight: null,
      timer: null,
      idleTimer: null,
    };
    pollers.set(opts.pluginToken, poller);
  }

  clearIdleTimer(poller);
  poller.refs += 1;
  const wasIdle = poller.refs === 1 && !poller.timer;
  await refresh(poller, wasIdle && poller.lastOkAt === 0);
  if (poller.refs > 0 && !poller.timer) {
    schedule(poller, poller.backoffMs);
  }

  return {
    config: () => poller.config,
    release: () => releaseShowcaseConfig(opts.pluginToken),
  };
}

function releaseShowcaseConfig(pluginToken: string): void {
  const poller = pollers.get(pluginToken);
  if (!poller) return;
  poller.refs = Math.max(0, poller.refs - 1);
  if (poller.refs > 0) return;

  clearTimer(poller);
  clearIdleTimer(poller);
  poller.idleTimer = setTimeout(() => {
    if (poller.refs > 0) return;
    clearTimer(poller);
    pollers.delete(pluginToken);
  }, SHOWCASE_IDLE_CACHE_MS);
}
