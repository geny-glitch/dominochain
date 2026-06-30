class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include SetLocale

  before_action :configure_permitted_parameters, if: :devise_controller?

  def after_sign_in_path_for(resource)
    return beta_dashboard_path if resource.beta?
    return admin_path if resource.admin?
    stored_location_for(resource) || dashboard_path
  end

  protected

  def bg_env_staging?
    ENV["BG_ENV"] == "staging"
  end
  helper_method :bg_env_staging?

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:email, :role])
    devise_parameter_sanitizer.permit(:account_update, keys: [:email, :nickname])
  end
end
