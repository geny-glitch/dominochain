# frozen_string_literal: true

class LeveragePhotoBundle < ApplicationRecord
  belongs_to :user
  has_many :leverage_photos, foreign_key: :bundle_id, inverse_of: :bundle, dependent: :destroy
end
