import { createHash } from "node:crypto";
import util from "node:util";

/** Active via env PURYFI_LOG_PLUGIN_PAYLOAD=1 (voir .env.example). */
export function puryfiLogPluginPayload(): boolean {
  const v = (process.env.PURYFI_LOG_PLUGIN_PAYLOAD ?? "").toLowerCase().trim();
  return v === "1" || v === "true" || v === "yes";
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return `{${keys
    .map((k) => `${JSON.stringify(k)}:${stableStringify(obj[k])}`)
    .join(",")}}`;
}

export function fingerprintStaticMediaPayload(payload: unknown): string {
  return createHash("sha256")
    .update(stableStringify(payload))
    .digest("hex")
    .slice(0, 16);
}

function summarizeRects(objects: unknown): string {
  if (!Array.isArray(objects) || objects.length === 0) {
    return "no objects";
  }
  let maxR = 0;
  let maxB = 0;
  let minX = Number.POSITIVE_INFINITY;
  let minY = Number.POSITIVE_INFINITY;
  for (const o of objects) {
    if (!o || typeof o !== "object") continue;
    const r = (o as { rect?: { x?: number; y?: number; width?: number; height?: number } }).rect;
    if (!r || typeof r.x !== "number" || typeof r.y !== "number") continue;
    const w = typeof r.width === "number" ? r.width : 0;
    const h = typeof r.height === "number" ? r.height : 0;
    minX = Math.min(minX, r.x);
    minY = Math.min(minY, r.y);
    maxR = Math.max(maxR, r.x + w);
    maxB = Math.max(maxB, r.y + h);
  }
  if (!Number.isFinite(minX)) {
    return "could not parse rects";
  }
  const looksNormalized = maxR <= 1 && maxB <= 1;
  return [
    `union of detection rects: x∈[${minX.toFixed(4)},${maxR.toFixed(4)}] y∈[${minY.toFixed(4)},${maxB.toFixed(4)}]`,
    looksNormalized
      ? "(everything ≤1 → coords likely normalized 0–1, not pixels — image size not in payload)"
      : "(values >1 → likely pixel coords; max edge is a lower bound on displayed media size)",
  ].join(" ");
}

/** État par connexion WebSocket pour repérer re-scans / reloads répétés. */
export class StaticScanDedupeLogState {
  private previousFp: string | undefined;
  private readonly recentHits = new Map<string, number[]>();

  fingerprintStats(
    fingerprint: string,
    windowMs: number,
  ): { sameAsImmediatelyPrevious: boolean; hitsInWindow: number } {
    const now = Date.now();
    const sameAsImmediatelyPrevious = fingerprint === this.previousFp;
    this.previousFp = fingerprint;

    let hits = this.recentHits.get(fingerprint) ?? [];
    hits = hits.filter((t) => now - t <= windowMs);
    hits.push(now);
    this.recentHits.set(fingerprint, hits);

    return {
      sameAsImmediatelyPrevious,
      hitsInWindow: hits.length,
    };
  }
}

export function logStaticMediaScanDebug(
  payload: unknown,
  dedupe: StaticScanDedupeLogState,
  windowMs: number,
): void {
  const ts = new Date().toISOString();
  const fp = fingerprintStaticMediaPayload(payload);
  const { sameAsImmediatelyPrevious, hitsInWindow } = dedupe.fingerprintStats(fp, windowMs);
  const topKeys =
    payload && typeof payload === "object" && !Array.isArray(payload)
      ? Object.keys(payload as object).join(", ")
      : typeof payload;

  console.log(`[${ts}] [PuryFi DEBUG] staticMediaScan ─────────────────`);
  console.log(`[${ts}] [PuryFi DEBUG] fingerprint=${fp} sameScanAsPreviousMessage=${sameAsImmediatelyPrevious} hitsInWindow(${windowMs}ms)=${hitsInWindow}`);
  console.log(`[${ts}] [PuryFi DEBUG] top-level keys: ${topKeys}`);

  const objects = (payload as { objects?: unknown })?.objects;
  console.log(`[${ts}] [PuryFi DEBUG] object count: ${Array.isArray(objects) ? objects.length : "n/a"}`);
  console.log(`[${ts}] [PuryFi DEBUG] ${summarizeRects(objects)}`);
  console.log(
    `[${ts}] [PuryFi DEBUG] full payload:\n${util.inspect(payload, { depth: 12, colors: false, maxArrayLength: 200 })}`,
  );
}

export function parseDedupeWindowMs(): number {
  const raw = process.env.PURYFI_SCAN_DEDUP_LOG_MS;
  if (raw === undefined || raw === "") return 120_000;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : 120_000;
}
