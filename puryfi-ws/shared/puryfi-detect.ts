import { labelName } from "./labels.js";

/** Detected region from PuryFi staticMediaScan */
export type ScanObject = {
  label: number;
  score: number;
};

export type PishockLevelSetting = {
  intensity: number;
  duration: number;
};

export type PluginConfigShape = {
  /** Seconds to add per label id (string keys for JSON portability) */
  secondsPerLabel: Record<string, number>;
  /** PiShock level 0–3 per label id */
  shockLevelPerLabel: Record<string, number>;
  /** Intensity/duration presets for levels 1–3 */
  pishockLevelSettings: Record<string, PishockLevelSetting>;
  minScore: number;
};

export type DetectionBreakdown = {
  labelId: number;
  labelName: string;
  score: number;
  secondsApplied: number;
  shockLevel: number;
};

export type ScanShock = {
  level: number;
  intensity: number;
  duration: number;
};

export type ScanResult = {
  /** Objects that passed minScore (may have 0 configured seconds) */
  matched: DetectionBreakdown[];
  totalSeconds: number;
  shock: ScanShock | null;
  /** Human-readable line for logs */
  summaryLine: string;
};

const DEFAULT_PISHOCK_LEVEL_SETTINGS: Record<string, PishockLevelSetting> = {
  "1": { intensity: 10, duration: 1 },
  "2": { intensity: 30, duration: 1 },
  "3": { intensity: 60, duration: 1 },
};

function clampShockLevel(value: unknown): number {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(3, n));
}

function resolveShock(level: number, settings: Record<string, PishockLevelSetting>): ScanShock | null {
  if (level < 1) return null;
  const preset = settings[String(level)] ?? DEFAULT_PISHOCK_LEVEL_SETTINGS[String(level)];
  if (!preset) return null;
  const intensity = Math.max(1, Math.floor(Number(preset.intensity)));
  const duration = Math.max(1, Math.min(15, Math.floor(Number(preset.duration))));
  if (!Number.isFinite(intensity) || !Number.isFinite(duration)) return null;
  return { level, intensity, duration };
}

/**
 * Sum configured seconds and resolve the highest PiShock level for each object that meets minScore.
 */
export function analyzeScan(
  objects: ScanObject[],
  config: PluginConfigShape,
): ScanResult {
  const minScore = config.minScore;
  const matched: DetectionBreakdown[] = [];
  let maxShockLevel = 0;

  for (const obj of objects) {
    if (obj.score < minScore) continue;

    const key = String(obj.label);
    if (!(key in config.secondsPerLabel)) continue;
    const configured = config.secondsPerLabel[key]!;

    const sec = Math.max(0, Math.floor(Number(configured)));
    const shockLevel = clampShockLevel(config.shockLevelPerLabel[key] ?? 0);
    if (sec <= 0 && shockLevel <= 0) continue;

    if (shockLevel > maxShockLevel) maxShockLevel = shockLevel;

    matched.push({
      labelId: obj.label,
      labelName: labelName(obj.label),
      score: obj.score,
      secondsApplied: sec,
      shockLevel,
    });
  }

  const totalSeconds = matched.reduce((s, m) => s + m.secondsApplied, 0);
  const shock = resolveShock(maxShockLevel, config.pishockLevelSettings);

  const parts = matched.map((m) => {
    const bits = [`${m.labelName}(${m.score.toFixed(2)})`];
    if (m.secondsApplied > 0) bits.push(`+${m.secondsApplied}s`);
    if (m.shockLevel > 0) bits.push(`⚡${m.shockLevel}`);
    return bits.join(" ");
  });
  const summaryLine =
    parts.length === 0
      ? "(aucune détection au-dessus du seuil / configurée)"
      : parts.join(", ");

  return { matched, totalSeconds, shock, summaryLine };
}

/** Default config: all labels 0s, minScore 0.5 */
export function defaultSecondsPerLabel(): Record<string, number> {
  const out: Record<string, number> = {};
  for (let id = 0; id <= 25; id++) out[String(id)] = 0;
  return out;
}

export function defaultShockLevelPerLabel(): Record<string, number> {
  const out: Record<string, number> = {};
  for (let id = 0; id <= 25; id++) out[String(id)] = 0;
  return out;
}

export function defaultPishockLevelSettings(): Record<string, PishockLevelSetting> {
  return {
    "1": { ...DEFAULT_PISHOCK_LEVEL_SETTINGS["1"]! },
    "2": { ...DEFAULT_PISHOCK_LEVEL_SETTINGS["2"]! },
    "3": { ...DEFAULT_PISHOCK_LEVEL_SETTINGS["3"]! },
  };
}
