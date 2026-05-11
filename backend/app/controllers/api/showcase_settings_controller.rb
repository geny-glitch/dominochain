# frozen_string_literal: true

module Api
  class ShowcaseSettingsController < ApplicationController
    include ApiAuthenticatable

    def show
      return head :forbidden unless current_user.beta?

      caps = BetaCapabilities.for(current_user)
      render json: {
        showcase_quiz_enabled: current_user.showcase_quiz_enabled,
        showcase_snake_enabled: current_user.showcase_snake_enabled,
        showcase_dino_enabled: current_user.showcase_dino_enabled,
        showcase_tetris_enabled: current_user.showcase_tetris_enabled,
        showcase_backdoor_enabled: current_user.showcase_backdoor_enabled,
        showcase_quiz_seconds_per_point: current_user.showcase_quiz_seconds_per_point,
        showcase_snake_seconds_per_fruit: current_user.showcase_snake_seconds_per_fruit,
        showcase_dino_seconds_per_obstacle: current_user.showcase_dino_seconds_per_obstacle,
        showcase_tetris_seconds_per_line: current_user.showcase_tetris_seconds_per_line,
        puryfi_min_score: current_user.puryfi_min_score,
        puryfi_seconds_per_label: current_user.puryfi_seconds_per_label,
        capabilities: caps.as_json
      }
    end

    def update
      return head :forbidden unless current_user.beta?

      quiz = params.key?(:showcase_quiz_enabled) ? cast_bool(params[:showcase_quiz_enabled]) : current_user.showcase_quiz_enabled
      snake = params.key?(:showcase_snake_enabled) ? cast_bool(params[:showcase_snake_enabled]) : current_user.showcase_snake_enabled
      dino = params.key?(:showcase_dino_enabled) ? cast_bool(params[:showcase_dino_enabled]) : current_user.showcase_dino_enabled
      tetris = params.key?(:showcase_tetris_enabled) ? cast_bool(params[:showcase_tetris_enabled]) : current_user.showcase_tetris_enabled
      backdoor = params.key?(:showcase_backdoor_enabled) ? cast_bool(params[:showcase_backdoor_enabled]) : current_user.showcase_backdoor_enabled
      attrs = {
        showcase_quiz_enabled: quiz,
        showcase_snake_enabled: snake,
        showcase_dino_enabled: dino,
        showcase_tetris_enabled: tetris,
        showcase_backdoor_enabled: backdoor
      }
      if params.key?(:showcase_snake_seconds_per_fruit)
        attrs[:showcase_snake_seconds_per_fruit] = params[:showcase_snake_seconds_per_fruit].to_i
      end
      if params.key?(:showcase_quiz_seconds_per_point)
        attrs[:showcase_quiz_seconds_per_point] = params[:showcase_quiz_seconds_per_point].to_i
      end
      if params.key?(:showcase_dino_seconds_per_obstacle)
        attrs[:showcase_dino_seconds_per_obstacle] = params[:showcase_dino_seconds_per_obstacle].to_i
      end
      if params.key?(:showcase_tetris_seconds_per_line)
        attrs[:showcase_tetris_seconds_per_line] = params[:showcase_tetris_seconds_per_line].to_i
      end
      if params.key?(:puryfi_min_score)
        attrs[:puryfi_min_score] = params[:puryfi_min_score].to_f
      end
      if params.key?(:puryfi_seconds_per_label)
        attrs[:puryfi_seconds_per_label] = sanitize_puryfi_seconds_per_label(params[:puryfi_seconds_per_label])
      end
      current_user.update!(attrs)
      caps = BetaCapabilities.for(current_user)
      render json: {
        showcase_quiz_enabled: current_user.showcase_quiz_enabled,
        showcase_snake_enabled: current_user.showcase_snake_enabled,
        showcase_dino_enabled: current_user.showcase_dino_enabled,
        showcase_tetris_enabled: current_user.showcase_tetris_enabled,
        showcase_backdoor_enabled: current_user.showcase_backdoor_enabled,
        showcase_quiz_seconds_per_point: current_user.showcase_quiz_seconds_per_point,
        showcase_snake_seconds_per_fruit: current_user.showcase_snake_seconds_per_fruit,
        showcase_dino_seconds_per_obstacle: current_user.showcase_dino_seconds_per_obstacle,
        showcase_tetris_seconds_per_line: current_user.showcase_tetris_seconds_per_line,
        puryfi_min_score: current_user.puryfi_min_score,
        puryfi_seconds_per_label: current_user.puryfi_seconds_per_label,
        capabilities: caps.as_json
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(" ") }, status: :unprocessable_entity
    end

    private

    def cast_bool(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def sanitize_puryfi_seconds_per_label(raw)
      h = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
      h = {} unless h.is_a?(Hash)
      out = {}
      (0..25).each do |i|
        key = i.to_s
        next unless h.key?(key) || h.key?(i)

        v = h[key] || h[i]
        n = v.to_i
        out[key] = n if n >= 0
      end
      current_user.puryfi_seconds_per_label.merge(out)
    end
  end
end
