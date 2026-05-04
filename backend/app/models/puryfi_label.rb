# frozen_string_literal: true

# Human-readable names for PuryFi static label ids (0–25), aligned with puryfi-ws/shared/labels.ts
class PuryfiLabel
  NAMES = [
    "Ventre",
    "Ventre (couvert)",
    "Fesses",
    "Fesses (couvertes)",
    "Poitrine féminine",
    "Poitrine féminine (couverte)",
    "Génitaux féminins",
    "Génitaux féminins (couverts)",
    "Génitaux masculins (couverts)",
    "Génitaux masculins",
    "Poitrine masculine",
    "Poitrine masculine (couverte)",
    "Visage féminin",
    "Visage masculin",
    "Pied (couvert)",
    "Pied",
    "Aisselle (couverte)",
    "Aisselle",
    "Anus (couvert)",
    "Anus",
    "Œil",
    "Bouche",
    "Mamelon (couvert)",
    "Mamelon",
    "Main (couverte)",
    "Main"
  ].freeze

  def self.name_for(id)
    NAMES[id] || "Label #{id}"
  end
end
