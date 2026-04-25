# frozen_string_literal: true

module Api
  class ShowcaseSettingsController < ApplicationController
    include ApiAuthenticatable

    def show
      return head :forbidden unless current_user.beta?

      render json: {
        showcase_quiz_enabled: current_user.showcase_quiz_enabled,
        showcase_snake_enabled: current_user.showcase_snake_enabled,
        showcase_backdoor_enabled: current_user.showcase_backdoor_enabled,
        showcase_snake_seconds_per_fruit: current_user.showcase_snake_seconds_per_fruit
      }
    end

    def update
      return head :forbidden unless current_user.beta?

      quiz = params.key?(:showcase_quiz_enabled) ? cast_bool(params[:showcase_quiz_enabled]) : current_user.showcase_quiz_enabled
      snake = params.key?(:showcase_snake_enabled) ? cast_bool(params[:showcase_snake_enabled]) : current_user.showcase_snake_enabled
      backdoor = params.key?(:showcase_backdoor_enabled) ? cast_bool(params[:showcase_backdoor_enabled]) : current_user.showcase_backdoor_enabled
      attrs = { showcase_quiz_enabled: quiz, showcase_snake_enabled: snake, showcase_backdoor_enabled: backdoor }
      if params.key?(:showcase_snake_seconds_per_fruit)
        attrs[:showcase_snake_seconds_per_fruit] = params[:showcase_snake_seconds_per_fruit].to_i
      end
      current_user.update!(attrs)
      render json: {
        showcase_quiz_enabled: current_user.showcase_quiz_enabled,
        showcase_snake_enabled: current_user.showcase_snake_enabled,
        showcase_backdoor_enabled: current_user.showcase_backdoor_enabled,
        showcase_snake_seconds_per_fruit: current_user.showcase_snake_seconds_per_fruit
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
