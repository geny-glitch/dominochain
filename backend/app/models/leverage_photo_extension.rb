# frozen_string_literal: true

class LeveragePhotoExtension < ApplicationRecord
  belongs_to :leverage_photo

  validates :added_seconds, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :locked_until_before, :locked_until_after, :drand_round_added, presence: true
end
