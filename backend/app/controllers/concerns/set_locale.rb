# frozen_string_literal: true

module SetLocale
  extend ActiveSupport::Concern

  SUPPORTED_LOCALES = %i[en fr es].freeze

  included do
    before_action :set_locale
  end

  private

  def set_locale
    I18n.locale = resolve_locale
  end

  def resolve_locale
    if user_signed_in?
      ul = normalize_locale(current_user.beta_ui_prefs&.dig("locale"))
      return ul if ul
    end

    if (pl = normalize_locale(params[:locale]))
      session[:locale] = pl.to_s
      return pl
    end

    if (sl = normalize_locale(session[:locale]))
      return sl
    end

    if (al = locale_from_accept_language)
      session[:locale] = al.to_s
      return al
    end

    I18n.default_locale
  end

  # Parses Accept-Language (e.g. "fr-FR,fr;q=0.9,en;q=0.8") and returns the
  # first supported primary language tag, preferring higher q-values.
  def locale_from_accept_language
    header = request.headers["Accept-Language"]
    return nil if header.blank?

    candidates = header.to_s.split(",").filter_map do |part|
      lang, *params = part.strip.split(";")
      next if lang.blank?

      q = 1.0
      params.each do |param|
        key, value = param.strip.split("=", 2)
        q = value.to_f if key == "q" && value.present?
      end

      primary = lang.downcase.tr("_", "-").split("-").first
      next unless primary.present?

      [primary.to_sym, q]
    end

    candidates
      .sort_by { |(_locale, q)| -q }
      .map(&:first)
      .find { |locale| SUPPORTED_LOCALES.include?(locale) }
  end

  def normalize_locale(value)
    return nil if value.blank?

    sym = value.to_s.downcase.tr("_", "-").split("-").first.to_sym
    SUPPORTED_LOCALES.include?(sym) ? sym : nil
  end
end
