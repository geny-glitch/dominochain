# frozen_string_literal: true

class UnlocksController < Devise::UnlocksController
  layout :layout_for_devise

  private

  def layout_for_devise
    return "beta_dashboard" if user_signed_in? && current_user&.beta?

    "application"
  end
end
