class Wallpaper < ApplicationRecord
  belongs_to :device
  has_one_attached :image

  def variant_for(device)
    return image unless device.screen_width.present? && device.screen_height.present?
    image.variant(
      resize_to_fill: [device.screen_width, device.screen_height]
    )
  end
end
