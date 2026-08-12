# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "Locale completeness" do
  LOCALES = %i[en fr es].freeze
  LOCALES_ROOT = Rails.root.join("config/locales")

  # Root-level stub (en.yml hello) is not product copy and is excluded.
  # devise.en.yml is merged into the English key set.
  EXTRA_FILES = {
    en: [LOCALES_ROOT.join("devise.en.yml")]
  }.freeze

  def flatten_keys(value, prefix = nil)
    case value
    when Hash
      value.flat_map { |key, child| flatten_keys(child, [prefix, key].compact.join(".")) }
    when Array
      # Arrays of hashes (e.g. terms.sections) contribute indexed keys for parity.
      value.each_with_index.flat_map do |item, index|
        flatten_keys(item, [prefix, index].compact.join("."))
      end
    else
      [prefix]
    end
  end

  def keys_for_locale(locale)
    dir = LOCALES_ROOT.join(locale.to_s)
    files = Dir.glob(dir.join("**/*.yml")).sort
    files.concat(Array(EXTRA_FILES[locale]).map(&:to_s))

    keys = Set.new
    files.each do |path|
      data = YAML.safe_load_file(path, aliases: true)
      next unless data.is_a?(Hash)

      root = data[locale.to_s] || data[locale.to_s]
      next unless root.is_a?(Hash)

      keys.merge(flatten_keys(root))
    end
    keys
  end

  it "keeps the same translation key set across en, fr, and es" do
    key_sets = LOCALES.index_with { |locale| keys_for_locale(locale) }
    reference = key_sets[:en]

    LOCALES.each do |locale|
      missing = (reference - key_sets[locale]).sort
      extra = (key_sets[locale] - reference).sort

      expect(missing).to be_empty, "#{locale} is missing keys present in en:\n#{missing.join("\n")}"
      expect(extra).to be_empty, "#{locale} has extra keys not present in en:\n#{extra.join("\n")}"
    end
  end
end
