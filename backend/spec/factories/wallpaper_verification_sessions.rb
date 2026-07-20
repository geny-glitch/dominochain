# frozen_string_literal: true

FactoryBot.define do
  factory :wallpaper_verification_session do
    user
    device { association :device, user: user }
    wallpaper do
      w = association :wallpaper, device: device
      WallpaperVerificationTestImages.attach_png(w, attachment_name: :image, width: 100, height: 200, color: [90, 90, 90])
      w
    end
    status { WallpaperVerificationSession::ACTIVE_STATUS }
    started_at { Time.current }
    ends_at { 4.hours.from_now }
    config_snapshot { WallpaperVerificationSession.build_config_snapshot(user.ensure_wallpaper_enforcement_config!) }

    trait :expired do
      status { "expired" }
      started_at { 5.hours.ago }
      ends_at { 1.hour.ago }
    end
  end
end
