# frozen_string_literal: true

module Api
  class ShowcaseSettingsController < ApplicationController
    include ApiAuthenticatable

    def show
      return head :forbidden unless current_user.beta?

      render json: {
        showcase_quiz_enabled: current_user.showcase_quiz_enabled,
        showcase_snake_enabled: current_user.showcase_snake_enabled,
        showcase_dino_enabled: current_user.showcase_dino_enabled,
        showcase_backdoor_enabled: current_user.showcase_backdoor_enabled,
        showcase_quiz_seconds_per_point: current_user.showcase_quiz_seconds_per_point,
        showcase_snake_seconds_per_fruit: current_user.showcase_snake_seconds_per_fruit,
        showcase_dino_seconds_per_obstacle: current_user.showcase_dino_seconds_per_obstacle
      }
    end

    def update
      return head :forbidden unless current_user.beta?

      quiz = params.key?(:showcase_quiz_enabled) ? cast_bool(params[:showcase_quiz_enabled]) : current_user.showcase_quiz_enabled
      snake = params.key?(:showcase_snake_enabled) ? cast_bool(params[:showcase_snake_enabled]) : current_user.showcase_snake_enabled
      dino = params.key?(:showcase_dino_enabled) ? cast_bool(params[:showcase_dino_enabled]) : current_user.showcase_dino_enabled
      backdoor = params.key?(:showcase_backdoor_enabled) ? cast_bool(params[:showcase_backdoor_enabled]) : current_user.showcase_backdoor_enabled
      attrs = { showcase_quiz_enabled: quiz, showcase_snake_enabled: snake, showcase_dino_enabled: dino, showcase_backdoor_enabled: backdoor }
      if params.key?(:showcase_snake_seconds_per_fruit)
        attrs[:showcase_snake_seconds_per_fruit] = params[:showcase_snake_seconds_per_fruit].to_i
      end
      if params.key?(:showcase_quiz_seconds_per_point)
        attrs[:showcase_quiz_seconds_per_point] = params[:showcase_quiz_seconds_per_point].to_i
      end
      if params.key?(:showcase_dino_seconds_per_obstacle)
        attrs[:showcase_dino_seconds_per_obstacle] = params[:showcase_dino_seconds_per_obstacle].to_i
      end
      current_user.update!(attrs)
      render json: {
        showcase_quiz_enabled: current_user.showcase_quiz_enabled,
        showcase_snake_enabled: current_user.showcase_snake_enabled,
        showcase_dino_enabled: current_user.showcase_dino_enabled,
        showcase_backdoor_enabled: current_user.showcase_backdoor_enabled,
        showcase_quiz_seconds_per_point: current_user.showcase_quiz_seconds_per_point,
        showcase_snake_seconds_per_fruit: current_user.showcase_snake_seconds_per_fruit,
        showcase_dino_seconds_per_obstacle: current_user.showcase_dino_seconds_per_obstacle
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(" ") }, status: :unprocessable_entity
    end

    private

    def cast_bool(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
