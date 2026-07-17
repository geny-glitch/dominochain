class Wallpaper < ApplicationRecord
  include ImagePreviewVariant

  belongs_to :device
  belongs_to :leverage_photo, optional: true
  has_many :wallpaper_applications, dependent: :destroy
  has_many :device_screenshots, dependent: :nullify
  has_one_attached :image do |attachable|
    ImagePreviewVariant::AttachmentConfig.call(attachable)
  end
  # Kept while a Time Vault photo is the live wallpaper so unlock can restore the original
  # after lock swapped the visible image to censored/teaser.
  has_one_attached :leverage_original_image

  after_create_commit :send_push_notification

  def variant_for(device)
    return image unless device.screen_width.present? && device.screen_height.present?
    image.variant(
      resize_to_fill: [device.screen_width, device.screen_height]
    )
  end

  def linked_to_leverage_photo?(photo)
    leverage_photo_id.present? && leverage_photo_id == photo.id
  end

  private

  def send_push_notification
    return unless image.attached?
    FcmService.send_background_changed_notifications(device: device)
  end
end
