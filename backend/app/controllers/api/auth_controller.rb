# frozen_string_literal: true

module Api
  class AuthController < ApplicationController
    skip_before_action :verify_authenticity_token

    def login
      user = find_user_for_api_login
      if user&.valid_password?(params[:password])
        device = link_device_to_user(user)
        PostHog.identify(distinct_id: user.posthog_distinct_id, properties: user.posthog_properties)
        PostHog.capture(distinct_id: user.posthog_distinct_id, event: 'user_logged_in', properties: { login_method: 'api' })
        render json: auth_response(user, device)
      else
        render json: { error: "E-mail ou mot de passe incorrect" }, status: :unauthorized
      end
    end

    def register
      user = User.new(
        email: resolved_register_email,
        nickname: params[:nickname].presence,
        password: params[:password],
        password_confirmation: params[:password_confirmation],
        role: :beta
      )
      if user.save
        device = link_device_to_user(user)
        PostHog.identify(distinct_id: user.posthog_distinct_id, properties: user.posthog_properties)
        PostHog.capture(distinct_id: user.posthog_distinct_id, event: 'user_registered', properties: { signup_method: 'api' })
        render json: auth_response(user, device), status: :created
      else
        render json: { error: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    def logout
      token = request.headers["Authorization"]&.sub(/\ABearer\s+/i, "") || request.headers["X-Device-Token"]
      device_id = request.headers["X-Device-Id"] || params[:device_id]
      if token.present? && device_id.present?
        device = Device.find_by(device_id: device_id, auth_token: token)
        if device&.user
          PostHog.capture(distinct_id: device.user.posthog_distinct_id, event: 'user_logged_out')
        end
        Device.where(device_id: device_id, auth_token: token).update_all(auth_token: nil)
      end
      head :no_content
    end

    private

    def find_user_for_api_login
      email = params[:email].to_s.strip.downcase
      return User.find_for_database_authentication(email: email) if email.present?

      nickname = params[:nickname].to_s.strip
      User.find_by(nickname: nickname) if nickname.present?
    end

    def resolved_register_email
      email = params[:email].to_s.strip.downcase
      return email if email.present?

      nickname = params[:nickname].to_s.strip
      return nil if nickname.blank?

      local_part = nickname.downcase.gsub(/[^a-z0-9_]/, "_")
      local_part = "user" if local_part.blank?
      "#{local_part}@dominochain.app"
    end

    def link_device_to_user(user)
      device_id = params[:device_id]
      return nil unless device_id.present?

      device = Device.find_or_initialize_by(device_id: device_id)
      device.user = user
      device.auth_token = SecureRandom.hex(32)
      device.screen_width = params[:screen_width]&.to_i if params[:screen_width].present?
      device.screen_height = params[:screen_height]&.to_i if params[:screen_height].present?
      device.fcm_token = params[:fcm_token] if params[:fcm_token].present?
      device.name = params[:name].presence if params.key?(:name)
      device.save!
      device.touch_last_seen!
      device
    end

    def auth_response(user, device)
      web_url = device ? "#{request.base_url}/w/#{user.nickname}" : nil
      {
        token: device&.auth_token,
        user: { nickname: user.nickname, email: user.email },
        device_id: device&.device_id,
        web_url: web_url
      }
    end
  end
end
