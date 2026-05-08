# frozen_string_literal: true

# Central place for vitrine game economics (seconds per score) and defaults.
# Used by showcase, API lock payload, cigarette tracker, and event pipelines.
class ShowcaseGameConfig
  QUIZ_SECONDS_PER_POINT = 1
  SNAKE_SECONDS_PER_FRUIT = 300
  DINO_SECONDS_PER_OBSTACLE = 300
  TETRIS_SECONDS_PER_LINE = 60

  BACKDOOR_MAX_SECONDS = 86_400 * 365

  class << self
    def snake_seconds_per_fruit_for(beta)
      s = beta.showcase_snake_seconds_per_fruit
      s = SNAKE_SECONDS_PER_FRUIT if s.blank? || s <= 0
      [ s, BACKDOOR_MAX_SECONDS ].min
    end

    def quiz_seconds_per_point_for(beta)
      s = beta.showcase_quiz_seconds_per_point
      s = QUIZ_SECONDS_PER_POINT if s.blank? || s <= 0
      [ s, BACKDOOR_MAX_SECONDS ].min
    end

    def dino_seconds_per_obstacle_for(beta)
      s = beta.showcase_dino_seconds_per_obstacle
      s = DINO_SECONDS_PER_OBSTACLE if s.blank? || s <= 0
      [ s, BACKDOOR_MAX_SECONDS ].min
    end

    def tetris_seconds_per_line_for(beta)
      s = beta.showcase_tetris_seconds_per_line
      s = TETRIS_SECONDS_PER_LINE if s.blank? || s <= 0
      [ s, BACKDOOR_MAX_SECONDS ].min
    end

    def seconds_for_game(beta, game_kind, requested_seconds:, lines_param: nil)
      case game_kind.to_s
      when "snake" then snake_seconds_per_fruit_for(beta)
      when "dino" then dino_seconds_per_obstacle_for(beta)
      when "tetris"
        per = tetris_seconds_per_line_for(beta)
        lines = lines_param.to_i
        if lines.positive?
          lines = [ [ lines, 1 ].max, 8 ].min
          lines * per
        else
          per
        end
      else
        points = requested_seconds&.to_i
        return nil if points.blank?

        points * quiz_seconds_per_point_for(beta)
      end
    end

    def game_enabled?(beta, game_type)
      case game_type.to_s
      when "snake" then beta.showcase_snake_enabled
      when "dino" then beta.showcase_dino_enabled
      when "tetris" then beta.showcase_tetris_enabled
      when "quiz" then beta.showcase_quiz_enabled
      else false
      end
    end

    def game_seconds_payload_for_user(user)
      quiz_sec = user.showcase_quiz_seconds_per_point
      quiz_sec = QUIZ_SECONDS_PER_POINT if quiz_sec.blank? || quiz_sec <= 0
      snake_sec = user.showcase_snake_seconds_per_fruit
      snake_sec = SNAKE_SECONDS_PER_FRUIT if snake_sec.blank? || snake_sec <= 0
      dino_sec = user.showcase_dino_seconds_per_obstacle
      dino_sec = DINO_SECONDS_PER_OBSTACLE if dino_sec.blank? || dino_sec <= 0
      tetris_sec = user.showcase_tetris_seconds_per_line
      tetris_sec = TETRIS_SECONDS_PER_LINE if tetris_sec.blank? || tetris_sec <= 0

      {
        showcase_quiz_seconds_per_point: quiz_sec,
        showcase_snake_seconds_per_fruit: snake_sec,
        showcase_dino_seconds_per_obstacle: dino_sec,
        showcase_tetris_seconds_per_line: tetris_sec
      }
    end

    def pishock_intensity(base, user)
      factor = [ user.pishock_intensity_factor.to_f, 0.01 ].max
      (base * factor).round.clamp(1, 100)
    end
  end
end
