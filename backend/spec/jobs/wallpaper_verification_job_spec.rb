# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperVerificationJob, type: :job do
  let(:device) { create(:device, screen_width: 540, screen_height: 960) }
  let(:wallpaper) { create(:wallpaper, device: device) }
  let(:screenshot) { create(:device_screenshot, device: device, captured_at: Time.current) }

  before do
    WallpaperVerificationTestImages.attach_png(
      wallpaper,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )
    WallpaperVerificationTestImages.attach_png(
      screenshot,
      attachment_name: :image,
      width: device.screen_width,
      height: device.screen_height,
      color: [120, 80, 200]
    )
    device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: 1.minute.ago)
  end

  it "persists a verified result for matching images" do
    described_class.perform_now(screenshot.id)

    screenshot.reload
    expect(screenshot.verification_status).to eq("verified")
    expect(screenshot.similarity_score).to be >= 0.9
    expect(screenshot.wallpaper_id).to eq(wallpaper.id)
    expect(screenshot.verified_at).to be_present
  end

  it "marks screenshots captured before the latest wallpaper change as inconclusive" do
    screenshot.update!(captured_at: 5.minutes.ago)
    device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: 1.minute.ago)

    described_class.perform_now(screenshot.id)

    screenshot.reload
    expect(screenshot.verification_status).to eq("inconclusive")
  end

  it "skips verification when no current wallpaper exists" do
    wallpaper.image.purge
    wallpaper.destroy!

    described_class.perform_now(screenshot.id)

    screenshot.reload
    expect(screenshot.verification_status).to eq("skipped")
  end
end

RSpec.describe WallpaperScreenshotRequestJob, type: :job do
  let(:device) { create(:device, fcm_token: "token") }

  it "requests a screenshot when none was captured after the wallpaper change" do
    allow(FcmService).to receive(:send_take_screenshot_notification)

    described_class.perform_now(device.id, 1.minute.ago.iso8601)

    expect(FcmService).to have_received(:send_take_screenshot_notification).with(device: device)
  end

  it "does not request a screenshot when a recent capture already exists" do
    create(:device_screenshot, device: device, captured_at: Time.current)
    allow(FcmService).to receive(:send_take_screenshot_notification)

    described_class.perform_now(device.id, 1.minute.ago.iso8601)

    expect(FcmService).not_to have_received(:send_take_screenshot_notification)
  end
end

RSpec.describe WallpaperStaleVerificationSweepJob, type: :job do
  let(:device) { create(:device) }

  it "enqueues verification for stale pending screenshots" do
    stale = create(:device_screenshot, device: device, verification_status: "pending", created_at: 1.minute.ago)
    fresh = create(:device_screenshot, device: device, verification_status: "pending", created_at: 5.seconds.ago)
    create(:device_screenshot, device: device, verification_status: "verified", created_at: 1.minute.ago)

    expect {
      described_class.perform_now(device.id)
    }.to have_enqueued_job(WallpaperVerificationJob).with(stale.id).once

    expect(WallpaperVerificationJob).not_to have_been_enqueued.with(fresh.id)
  end

  it "does nothing when the device does not exist" do
    expect {
      described_class.perform_now(-1)
    }.not_to have_enqueued_job(WallpaperVerificationJob)
  end
end
