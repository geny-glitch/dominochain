# frozen_string_literal: true

class RegistrationsController < Devise::RegistrationsController
  include SignupConsents

  before_action :configure_sign_up_params, only: [:create]
  layout :layout_for_registration

  def create
    unless signup_consents_accepted?
      build_resource(sign_up_params)
      apply_signup_consent_errors(resource)
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource, status: :unprocessable_entity
      return
    end

    super do |user|
      if user.persisted?
        PostHog.identify(distinct_id: user.posthog_distinct_id, properties: user.posthog_properties)
        PostHog.capture(distinct_id: user.posthog_distinct_id, event: 'user_registered', properties: { signup_method: 'web' })
      end
    end
  end

  def destroy
    expected_label = I18n.t("devise.registrations.delete_confirmation_label").to_s
    submitted_label = params.dig(:account_deletion, :confirmation_label).to_s.strip

    if submitted_label != expected_label
      flash[:alert] = I18n.t("devise.registrations.delete_confirmation_mismatch")
      redirect_to edit_user_registration_path
      return
    end

    super
  end

  protected

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:email, :role])
  end

  def build_resource(hash = {})
    super(hash.merge(role: :beta))
  end

  def layout_for_registration
    return "beta_dashboard" if user_signed_in? && current_user&.beta?

    "application"
  end
end
