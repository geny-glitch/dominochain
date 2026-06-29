class Wallpaper < ApplicationRecord
  include ImagePreviewVariant

  belongs_to :device
  has_many :wallpaper_applications, dependent: :destroy
  has_many :device_screenshots, dependent: :nullify
  has_one_attached :image do |attachable|
    ImagePreviewVariant::AttachmentConfig.call(attachable)
  end

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
    FcmService.send_background_changed_notifications(device: device)
  end
end
