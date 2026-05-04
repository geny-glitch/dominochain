import { labelName } from "./labels.js";

/** Detected region from PuryFi staticMediaScan */
export type ScanObject = {
  label: number;
  score: number;
};

export type PluginConfigShape = {
  /** Seconds to add per label id (string keys for JSON portability) */
  secondsPerLabel: Record<string, number>;
  minScore: number;
};

export type DetectionBreakdown = {
  labelId: number;
  labelName: string;
  score: number;
  secondsApplied: number;
};

export type ScanResult = {
  /** Objects that passed minScore (may have 0 configured seconds) */
  matched: DetectionBreakdown[];
  totalSeconds: number;
  /** Human-readable line for logs */
  summaryLine: string;
};

/**
 * Sum configured seconds for each object that meets minScore.
 */
export function analyzeScan(
  objects: ScanObject[],
  config: PluginConfigShape,
): ScanResult {
  const minScore = config.minScore;
  const matched: DetectionBreakdown[] = [];

  for (const obj of objects) {
    if (obj.score < minScore) continue;

    const key = String(obj.label);
    if (!(key in config.secondsPerLabel)) continue;
    const configured = config.secondsPerLabel[key]!;

    const sec = Math.max(0, Math.floor(Number(configured)));
    matched.push({
      labelId: obj.label,
      labelName: labelName(obj.label),
      score: obj.score,
      secondsApplied: sec,
    });
  }

  const totalSeconds = matched.reduce((s, m) => s + m.secondsApplied, 0);

  const parts = matched.map(
    (m) =>
      `${m.labelName}(${m.score.toFixed(2)}) +${m.secondsApplied}s`,
  );
  const summaryLine =
    parts.length === 0
      ? "(aucune détection au-dessus du seuil / configurée)"
      : parts.join(", ");

  return { matched, totalSeconds, summaryLine };
}

/** Default config: all labels 0s, minScore 0.5 */
export function defaultSecondsPerLabel(): Record<string, number> {
  const out: Record<string, number> = {};
  for (let id = 0; id <= 25; id++) out[String(id)] = 0;
  return out;
}
