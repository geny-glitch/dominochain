# frozen_string_literal: true

class RegistrationsController < Devise::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]
  layout :layout_for_registration

  protected

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:nickname, :role])
  end

  def build_resource(hash = {})
    super(hash.merge(role: :beta))
  end

  def layout_for_registration
    return "beta_dashboard" if user_signed_in? && current_user&.beta?

    "application"
  end
end
