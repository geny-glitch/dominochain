# frozen_string_literal: true

class CigaretteEntry < ApplicationRecord
  belongs_to :user

  validates :count, numericality: { only_integer: true, greater_than: 0 }
  validates :smoked_on, :smoked_at, presence: true
  validates :chaster_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(smoked_at: :desc, id: :desc) }
  scope :for_day, ->(date) { where(smoked_on: date) }
end
