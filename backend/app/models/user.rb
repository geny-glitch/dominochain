class User < ApplicationRecord
  SHOWCASE_SECONDS_DECREASE_COOLDOWN = 24.hours

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :rememberable, :validatable,
         authentication_keys: [:nickname]

  enum role: { beta: 0, boss: 1, admin: 2 }

  has_many :devices, dependent: :nullify
  has_many :tasks, dependent: :destroy
  has_one :control, foreign_key: :beta_id, dependent: :destroy
  has_many :controls, foreign_key: :boss_id, dependent: :destroy
  has_many :control_requests_sent, class_name: "ControlRequest", foreign_key: :beta_id, dependent: :destroy
  has_many :control_requests_received, class_name: "ControlRequest", foreign_key: :boss_id, dependent: :destroy
  has_many :chaster_locks, dependent: :destroy
  has_many :game_sessions, dependent: :destroy
  has_many :showcase_time_additions, dependent: :destroy
  has_many :cigarette_entries, dependent: :destroy
  has_many :strava_goals, dependent: :destroy
  has_many :strava_goal_checks, dependent: :destroy

  validates :nickname, presence: true, uniqueness: true
  validates :nickname, format: { with: /\A[a-zA-Z0-9_]+\z/, message: "ne peut contenir que lettres, chiffres et underscores" }
  validates :pishock_intensity_factor,
    numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :showcase_quiz_seconds_per_point,
    :showcase_snake_seconds_per_fruit,
    :showcase_dino_seconds_per_obstacle,
    :showcase_tetris_seconds_per_line,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 86_400 * 365 },
    if: :beta?
  validate :at_least_one_showcase_game_enabled, if: :beta?
  validate :showcase_quiz_seconds_decrease_cooldown, if: :beta?
  validate :showcase_snake_seconds_decrease_cooldown, if: :beta?
  validate :showcase_dino_seconds_decrease_cooldown, if: :beta?
  validate :showcase_tetris_seconds_decrease_cooldown, if: :beta?
  validates :puryfi_min_score,
    numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 },
    if: :beta?

  before_save :touch_showcase_quiz_seconds_changed_at, if: :will_save_change_to_showcase_quiz_seconds_per_point?
  before_save :touch_showcase_snake_seconds_changed_at, if: :will_save_change_to_showcase_snake_seconds_per_fruit?
  before_save :touch_showcase_dino_seconds_changed_at, if: :will_save_change_to_showcase_dino_seconds_per_obstacle?
  before_save :touch_showcase_tetris_seconds_changed_at, if: :will_save_change_to_showcase_tetris_seconds_per_line?

  def email_required?
    false
  end

  def email_changed?
    false
  end

  def will_save_change_to_email?
    false
  end

  def puryfi_ws_url
    return nil if puryfi_plugin_token.blank?

    base = ENV.fetch("PURYFI_WS_PUBLIC_BASE", "wss://bg-puryfi-ws.fly.dev").to_s.sub(%r{/+\z}, "")
    "#{base}/ws/#{puryfi_plugin_token}"
  end

  def ensure_puryfi_plugin_token!
    return if puryfi_plugin_token.present?

    update_column(:puryfi_plugin_token, SecureRandom.hex(32))
  end

  def regenerate_puryfi_plugin_token!
    update_column(:puryfi_plugin_token, SecureRandom.hex(32))
  end

  private

  def at_least_one_showcase_game_enabled
    return if showcase_quiz_enabled || showcase_snake_enabled || showcase_dino_enabled || showcase_tetris_enabled || showcase_backdoor_enabled

    errors.add(:base, "Au moins un jeu ou la page Backdoor doit rester activé sur la vitrine.")
  end

  def showcase_quiz_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_quiz_seconds_per_point,
      showcase_quiz_seconds_per_point_was,
      showcase_quiz_seconds_per_point,
      showcase_quiz_seconds_per_point_at_in_database
    )
  end

  def showcase_snake_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_snake_seconds_per_fruit,
      showcase_snake_seconds_per_fruit_was,
      showcase_snake_seconds_per_fruit,
      showcase_snake_seconds_per_fruit_at_in_database
    )
  end

  def showcase_dino_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_dino_seconds_per_obstacle,
      showcase_dino_seconds_per_obstacle_was,
      showcase_dino_seconds_per_obstacle,
      showcase_dino_seconds_per_obstacle_at_in_database
    )
  end

  def showcase_tetris_seconds_decrease_cooldown
    enforce_showcase_seconds_decrease_cooldown(
      :showcase_tetris_seconds_per_line,
      showcase_tetris_seconds_per_line_was,
      showcase_tetris_seconds_per_line,
      showcase_tetris_seconds_per_line_at_in_database
    )
  end

  def touch_showcase_quiz_seconds_changed_at
    self.showcase_quiz_seconds_per_point_at = Time.current
  end

  def touch_showcase_snake_seconds_changed_at
    self.showcase_snake_seconds_per_fruit_at = Time.current
  end

  def touch_showcase_dino_seconds_changed_at
    self.showcase_dino_seconds_per_obstacle_at = Time.current
  end

  def touch_showcase_tetris_seconds_changed_at
    self.showcase_tetris_seconds_per_line_at = Time.current
  end

  def enforce_showcase_seconds_decrease_cooldown(attribute, previous_value, current_value, last_changed_at)
    return unless public_send("#{attribute}_changed?")
    return if previous_value.nil?
    return if current_value >= previous_value
    return if last_changed_at.blank?

    return if Time.current >= last_changed_at + SHOWCASE_SECONDS_DECREASE_COOLDOWN

    unlock_at = last_changed_at + SHOWCASE_SECONDS_DECREASE_COOLDOWN
    errors.add(
      attribute,
      "tu ne peux pas réduire ce délai avant 24 h après le dernier changement (réessaie après #{unlock_at.strftime('%d/%m %H:%M')})."
    )
  end
end
