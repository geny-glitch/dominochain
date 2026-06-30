# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperVerificationJob, type: :job do
  include ActiveJob::TestHelper

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
    perform_enqueued_jobs
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

  it "defers verification until boss_preview variants are processed" do
    allow(ImagePreviewVariant).to receive(:preview_variant_processed?).and_return(false)

    expect {
      described_class.perform_now(screenshot.id)
    }.to have_enqueued_job(described_class).with(screenshot.id, defer_attempt: 1)

    expect(screenshot.reload.verification_status).to eq("pending")
  end

  it "marks inconclusive after too many variant defer attempts" do
    allow(ImagePreviewVariant).to receive(:preview_variant_processed?).and_return(false)

    described_class.perform_now(screenshot.id, defer_attempt: WallpaperVerificationJob::MAX_DEFER_ATTEMPTS)

    expect(screenshot.reload.verification_status).to eq("inconclusive")
  end

  describe ".enqueue_for" do
    it "skips enqueue when a job is already pending" do
      allow(described_class).to receive(:job_pending?).with(screenshot.id).and_return(true)

      expect(described_class.enqueue_for(screenshot.id)).to be(false)
      expect(described_class).not_to have_been_enqueued
    end

    it "enqueues when no job is pending" do
      allow(described_class).to receive(:job_pending?).with(screenshot.id).and_return(false)

      expect {
        expect(described_class.enqueue_for(screenshot.id)).to be(true)
      }.to have_enqueued_job(described_class).with(screenshot.id)
    end
  end
end
