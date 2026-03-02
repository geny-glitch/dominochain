class Wallpaper < ApplicationRecord
  belongs_to :device
  has_one_attached :image
end
