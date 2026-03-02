class Device < ApplicationRecord
  has_many :wallpapers, dependent: :destroy
end
