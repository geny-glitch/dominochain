class User < ApplicationRecord
  SHOWCASE_SNAKE_SECONDS_DECREASE_COOLDOWN = 24.hours

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

  validates :nickname, presence: true, uniqueness: true
  validates :nickname, format: { with: /\A[a-zA-Z0-9_]+\z/, message: "ne peut contenir que lettres, chiffres et underscores" }
  validates :showcase_snake_seconds_per_fruit,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 86_400 * 365 },
    if: :beta?
  validate :at_least_one_showcase_game_enabled, if: :beta?
  validate :showcase_snake_seconds_decrease_cooldown, if: :beta?

  before_save :touch_showcase_snake_seconds_changed_at, if: :will_save_change_to_showcase_snake_seconds_per_fruit?

  def email_required?
    false
  end

  def email_changed?
    false
  end

  def will_save_change_to_email?
    false
  end

  private

  def at_least_one_showcase_game_enabled
    return if showcase_quiz_enabled || showcase_snake_enabled || showcase_backdoor_enabled

    errors.add(:base, "Au moins un jeu ou la page Backdoor doit rester activé sur la vitrine.")
  end

  def showcase_snake_seconds_decrease_cooldown
    return unless showcase_snake_seconds_per_fruit_changed?
    was = showcase_snake_seconds_per_fruit_was
    return if was.nil?
    return if showcase_snake_seconds_per_fruit >= was
    last_at = showcase_snake_seconds_per_fruit_at_in_database
    return if last_at.blank?

    return if Time.current >= last_at + SHOWCASE_SNAKE_SECONDS_DECREASE_COOLDOWN

    unlock_at = last_at + SHOWCASE_SNAKE_SECONDS_DECREASE_COOLDOWN
    errors.add(
      :showcase_snake_seconds_per_fruit,
      "tu ne peux pas réduire ce délai avant 24 h après le dernier changement (réessaie après #{unlock_at.strftime('%d/%m %H:%M')})."
    )
  end

  def touch_showcase_snake_seconds_changed_at
    self.showcase_snake_seconds_per_fruit_at = Time.current
  end
end
