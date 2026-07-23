# frozen_string_literal: true

module Api
  module Wallpaper
    class ScenarioSchemasController < ApplicationController
      include ApiAuthenticatable

      def show
        render json: WallpaperPayload.scenario_schema_json(current_user)
      end
    end
  end
end
