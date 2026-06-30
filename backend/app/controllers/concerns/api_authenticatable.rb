# frozen_string_literal: true

module ApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    skip_before_action :verify_authenticity_token
    before_action :authenticate_api_user!
  end

  private

  def authenticate_api_user!
    token = request.headers["Authorization"]&.sub(/\ABearer\s+/i, "") || request.headers["X-Device-Token"]
    device_id = request.headers["X-Device-Id"] || params[:device_id] || params[:id]

    return head :unauthorized if token.blank?

    device = if device_id.present?
               Device.find_by(device_id: device_id, auth_token: token)
             else
               Device.find_by(auth_token: token)
             end
    if device&.user_id?
      @current_user = device.user
      @current_device = device
      device.touch_last_seen!
      return
    end

    user = User.beta.find_by(puryfi_plugin_token: token)
    if user
      @current_user = user
      @current_device = nil
      return
    end

    head :unauthorized
  end

  def current_device
    @current_device
  end

  def current_user
    @current_user
  end
end
