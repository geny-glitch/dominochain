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

    if (bl = locale_from_accept_language)
      session[:locale] = bl.to_s
      return bl
    end

    I18n.default_locale
  end

  def normalize_locale(value)
    return nil if value.blank?

    sym = value.to_s.downcase.tr("_", "-").split("-").first.to_sym
    SUPPORTED_LOCALES.include?(sym) ? sym : nil
  end

  def locale_from_accept_language
    header = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil if header.blank?

    header.split(",").each do |part|
      tag = part.split(";").first&.strip&.downcase
      next if tag.blank?

      lang = tag.split("-").first
      loc = normalize_locale(lang)
      return loc if loc
    end
    nil
  end
end
