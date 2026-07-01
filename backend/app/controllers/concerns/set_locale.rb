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

    I18n.default_locale
  end

  def normalize_locale(value)
    return nil if value.blank?

    sym = value.to_s.downcase.tr("_", "-").split("-").first.to_sym
    SUPPORTED_LOCALES.include?(sym) ? sym : nil
  end
end
