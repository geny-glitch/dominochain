# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperVerificationTimer do
  it "logs step timings and total duration" do
    allow(Rails.logger).to receive(:info)

    timer = described_class.new(42)
    timer.measure(:load_records) { :ok }
    timer.measure(:compare) { :ok }
    timer.finish(status: "verified", score: 0.91, ssim: 0.88, dhash: 3)

    expect(Rails.logger).to have_received(:info).with(
      a_string_matching(
        /\[WallpaperVerification\] screenshot=42 status=verified total_ms=\d+ steps=\{.*load_records.*compare.*\} score=0\.91 ssim=0\.88 dhash=3/
      )
    )
  end

  it "logs deferred actions" do
    allow(Rails.logger).to receive(:info)

    timer = described_class.new(7)
    timer.log_action(action: "deferred", wait_ms: 5000, attempt: 1)

    expect(Rails.logger).to have_received(:info).with(
      a_string_matching(/\[WallpaperVerification\] screenshot=7 action=deferred total_ms=\d+ steps=\{\} wait_ms=5000 attempt=1/)
    )
  end
end
