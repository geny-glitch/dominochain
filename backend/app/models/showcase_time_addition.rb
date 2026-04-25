# frozen_string_literal: true

class ShowcaseTimeAddition < ApplicationRecord
  belongs_to :user

  MAX_MESSAGE_LENGTH = 500
  MAX_NAME_LENGTH = 80

  validates :seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :player_name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :message, presence: true, length: { maximum: MAX_MESSAGE_LENGTH }
end
