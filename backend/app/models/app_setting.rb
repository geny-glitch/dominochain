# frozen_string_literal: true

class AppSetting < ApplicationRecord
  def self.instance
    first || create!(influencer_names: "")
  end

  def influencer_names_list
    return [] if influencer_names.blank?
    influencer_names.strip.split(/\r?\n/).map(&:strip).reject(&:blank?)
  end

  def influencer_names_list=(names)
    self.influencer_names = names.is_a?(Array) ? names.join("\n") : names.to_s
  end
end
