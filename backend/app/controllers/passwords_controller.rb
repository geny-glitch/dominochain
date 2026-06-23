# frozen_string_literal: true

class PasswordsController < Devise::PasswordsController
  layout :layout_for_devise

  # Devise sets a generic notice in flash after reset instructions are sent.
  # We suppress it so auth pages don't show a raw message above the layout.
  def create
    super do
      flash.delete(:notice)
    end
  end

  private

  def layout_for_devise
    return "beta_dashboard" if user_signed_in? && current_user&.beta?

    "application"
  end
end
