/**
 * PuryFi object.label values (see @pury-fi/plugin-sdk Object / Label enum).
 */
export type Gender = "female" | "male" | "neutral";

export type PuryfiLabelDef = {
  id: number;
  name: string;
  isNudity: boolean;
  gender: Gender;
};

export const LABELS: readonly PuryfiLabelDef[] = [
  { id: 0, name: "Ventre", isNudity: false, gender: "neutral" },
  { id: 1, name: "Ventre (couvert)", isNudity: false, gender: "neutral" },
  { id: 2, name: "Fesses", isNudity: true, gender: "neutral" },
  { id: 3, name: "Fesses (couvertes)", isNudity: false, gender: "neutral" },
  { id: 4, name: "Poitrine féminine", isNudity: true, gender: "female" },
  { id: 5, name: "Poitrine féminine (couverte)", isNudity: false, gender: "female" },
  { id: 6, name: "Génitaux féminins", isNudity: true, gender: "female" },
  { id: 7, name: "Génitaux féminins (couverts)", isNudity: false, gender: "female" },
  { id: 8, name: "Génitaux masculins (couverts)", isNudity: false, gender: "male" },
  { id: 9, name: "Génitaux masculins", isNudity: true, gender: "male" },
  { id: 10, name: "Poitrine masculine", isNudity: false, gender: "male" },
  { id: 11, name: "Poitrine masculine (couverte)", isNudity: false, gender: "male" },
  { id: 12, name: "Visage féminin", isNudity: false, gender: "female" },
  { id: 13, name: "Visage masculin", isNudity: false, gender: "male" },
  { id: 14, name: "Pied (couvert)", isNudity: false, gender: "neutral" },
  { id: 15, name: "Pied", isNudity: false, gender: "neutral" },
  { id: 16, name: "Aisselle (couverte)", isNudity: false, gender: "neutral" },
  { id: 17, name: "Aisselle", isNudity: false, gender: "neutral" },
  { id: 18, name: "Anus (couvert)", isNudity: false, gender: "neutral" },
  { id: 19, name: "Anus", isNudity: true, gender: "neutral" },
  { id: 20, name: "Œil", isNudity: false, gender: "neutral" },
  { id: 21, name: "Bouche", isNudity: false, gender: "neutral" },
  { id: 22, name: "Mamelon (couvert)", isNudity: false, gender: "neutral" },
  { id: 23, name: "Mamelon", isNudity: true, gender: "neutral" },
  { id: 24, name: "Main (couverte)", isNudity: false, gender: "neutral" },
  { id: 25, name: "Main", isNudity: false, gender: "neutral" },
] as const;

const byId = new Map<number, PuryfiLabelDef>(
  LABELS.map((l) => [l.id, l]),
);

export function labelName(id: number): string {
  return byId.get(id)?.name ?? `Label ${id}`;
}
