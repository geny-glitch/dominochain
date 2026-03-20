# frozen_string_literal: true

class ChasterLock < ApplicationRecord
  belongs_to :user

  scope :active, -> { where(status: "locked") }
  scope :recent, -> { order(end_date: :desc) }
  scope :history, -> { order(unlocked_at: :desc, end_date: :desc) }

  validates :chaster_lock_id, presence: true, uniqueness: { scope: :user_id }
end
