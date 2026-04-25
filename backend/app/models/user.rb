class User < ApplicationRecord
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
  validate :at_least_one_showcase_game_enabled, if: :beta?

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
end
