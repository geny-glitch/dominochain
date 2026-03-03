# frozen_string_literal: true

class DeviceScreenshot < ApplicationRecord
  belongs_to :device

  has_one_attached :image

  validates :captured_at, presence: true
end
