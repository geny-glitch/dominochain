# frozen_string_literal: true

# Human-readable names for PuryFi static label ids (0–25), aligned with puryfi-ws/shared/labels.ts
class PuryfiLabel
  CODES = %w[
    bellye bellyc butte buttc ftite ftitc fgene fgenc mgenc mgene mtite mtitc
    fface mface feetc feete apitc apite anusc anuse eye mouth nipplec nipple handc hand
  ].freeze

  IMAGE_BY_CODE = {
    "fface" => "face_female.png",
    "mface" => "face_male.png",
    "fgene" => "genitals_female.png",
    "fgenc" => "genitals_female_covered.png",
    "mgene" => "genitals_male.png",
    "mgenc" => "genitals_male_covered.png",
    "ftite" => "breasts_female.png",
    "ftitc" => "breasts_female_covered.png",
    "mtite" => "breasts_male.png",
    "mtitc" => "breasts_male_covered.png",
    "butte" => "buttocks_exposed.png",
    "buttc" => "buttocks_covered.png",
    "bellye" => "belly.png",
    "bellyc" => "belly_covered.png",
    "anuse" => "anus_exposed.png",
    "anusc" => "anus_covered.png",
    "apite" => "armpit_exposed.png",
    "apitc" => "armpit_covered.png",
    "feete" => "feet_exposed.png",
    "feetc" => "feet_covered.png"
  }.freeze

  def self.name_for(id)
    code = code_for(id)
    return "Label #{id}" if code.blank?

    I18n.t("beta.puryfi.labels.#{code}", default: "Label #{id}")
  end

  def self.code_for(id)
    CODES[id]
  end

  def self.image_url_for(id)
    code = code_for(id)
    filename = IMAGE_BY_CODE[code]
    return nil if filename.blank?

    "https://pury.fi/static/images/buttons/#{filename}"
  end
end
