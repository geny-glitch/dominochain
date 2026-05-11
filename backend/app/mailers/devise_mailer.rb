# frozen_string_literal: true

class DeviseMailer < Devise::Mailer
  SUPPORTED_LOCALES = %i[en fr es].freeze

  default from: -> { ENV.fetch("RESEND_FROM_EMAIL", "DominoChain <noreply@mail.dominochain.app>") }
  default reply_to: -> { ENV.fetch("RESEND_REPLYTO_EMAIL", "support@dominochain.app") }
  default template_path: "devise/mailer"
  layout false

  def confirmation_instructions(record, token, opts = {})
    @token = token
    branded_devise_mail(record, :confirmation_instructions, opts)
  end

  def reset_password_instructions(record, token, opts = {})
    @token = token
    branded_devise_mail(record, :reset_password_instructions, opts)
  end

  def unlock_instructions(record, token, opts = {})
    @token = token
    branded_devise_mail(record, :unlock_instructions, opts)
  end

  def email_changed(record, opts = {})
    @email = record.try(:unconfirmed_email?) ? record.unconfirmed_email : record.email
    branded_devise_mail(record, :email_changed, opts)
  end

  def password_change(record, opts = {})
    branded_devise_mail(record, :password_change, opts)
  end

  private

  def branded_devise_mail(record, action, opts)
    I18n.with_locale(locale_for(record)) do
      devise_mail(record, action, opts) do |format|
        format.text
        format.mjml
      end
    end
  end

  def locale_for(record)
    return I18n.default_locale unless record.respond_to?(:beta_ui_prefs)

    normalize_locale(record.beta_ui_prefs&.dig("locale")) || I18n.default_locale
  end

  def normalize_locale(value)
    return nil if value.blank?

    locale = value.to_s.downcase.tr("_", "-").split("-").first.to_sym
    SUPPORTED_LOCALES.include?(locale) ? locale : nil
  end
end
