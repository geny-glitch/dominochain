class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :rememberable, :validatable,
         authentication_keys: [:nickname]

  enum role: { beta: 0, boss: 1 }

  has_many :devices, dependent: :nullify
  has_one :control, foreign_key: :beta_id, dependent: :destroy
  has_many :controls, foreign_key: :boss_id, dependent: :destroy
  has_many :control_requests_sent, class_name: "ControlRequest", foreign_key: :beta_id, dependent: :destroy
  has_many :control_requests_received, class_name: "ControlRequest", foreign_key: :boss_id, dependent: :destroy

  validates :nickname, presence: true, uniqueness: true
  validates :nickname, format: { with: /\A[a-zA-Z0-9_]+\z/, message: "ne peut contenir que lettres, chiffres et underscores" }

  def email_required?
    false
  end

  def email_changed?
    false
  end

  def will_save_change_to_email?
    false
  end
end
