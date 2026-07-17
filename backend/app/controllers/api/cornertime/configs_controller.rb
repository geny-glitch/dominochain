# frozen_string_literal: true

module Api
  module Cornertime
    class ConfigsController < ApplicationController
      include ApiAuthenticatable

      def show
        config = current_user.ensure_cornertime_config!
        render json: CornertimePayload.config_json(config)
      end
    end
  end
end
