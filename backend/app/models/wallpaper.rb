class Wallpaper < ApplicationRecord
  belongs_to :device
  has_one_attached :image

  after_create_commit :send_push_notification

  def variant_for(device)
    return image unless device.screen_width.present? && device.screen_height.present?
    image.variant(
      resize_to_fill: [device.screen_width, device.screen_height]
    )
  end

  private

  def send_push_notification
    return unless image.attached?
    FcmService.send_new_wallpaper_notification(device: device)
  end
end
