# frozen_string_literal: true

class SessionsController < Devise::SessionsController
  layout :layout_for_devise

  private

  def layout_for_devise
    return "beta_dashboard" if user_signed_in? && current_user&.beta?

    "application"
  end
end
