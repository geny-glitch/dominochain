# frozen_string_literal: true

module SignupConsents
  extend ActiveSupport::Concern

  SIGNUP_CONSENT_KEYS = %i[age_confirmed terms_accepted].freeze

  included do
    helper_method :signup_consent_checked?
  end

  def signup_consent_checked?(key)
    CheckboxParamNormalizer.to_bool(params.dig(:signup_consents, key))
  end

  private

  def signup_consents_accepted?
    SIGNUP_CONSENT_KEYS.all? { |key| signup_consent_checked?(key) }
  end

  def apply_signup_consent_errors(resource)
    resource.errors.add(:base, I18n.t("devise.registrations.consent_age_required")) unless signup_consent_checked?(:age_confirmed)
    resource.errors.add(:base, I18n.t("devise.registrations.consent_terms_required")) unless signup_consent_checked?(:terms_accepted)
  end
end
