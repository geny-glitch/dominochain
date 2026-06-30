# frozen_string_literal: true

require "rails_helper"

RSpec.describe WallpaperVerificationSentry do
  let(:user) { create(:user, :beta, nickname: "luktest") }
  let(:device) { create(:device, user: user) }
  let(:screenshot) { create(:device_screenshot, device: device) }
  let(:scope) { instance_double(Sentry::Scope, set_context: nil, set_tags: nil) }

  before do
    allow(described_class).to receive(:sentry_enabled?).and_return(true)
    allow(Sentry).to receive(:with_scope).and_yield(scope)
  end

  it "reports compare_error to Sentry with the exception" do
    error = Vips::Error.new("extract_area: bad extract area")

    expect(Sentry).to receive(:capture_exception).with(error)
    expect(Sentry).not_to receive(:capture_message)

    described_class.report_unexpected_inconclusive!(
      screenshot: screenshot,
      reason: "compare_error",
      error: error
    )
  end

  it "does not report ambiguous_match" do
    expect(Sentry).not_to receive(:capture_message)
    expect(Sentry).not_to receive(:capture_exception)

    described_class.report_unexpected_inconclusive!(
      screenshot: screenshot,
      reason: "ambiguous_match"
    )
  end

  it "reports capture_before_wallpaper_change as a warning message" do
    expect(Sentry).to receive(:capture_message).with(
      "Wallpaper verification inconclusive: capture_before_wallpaper_change",
      level: :warning
    )

    described_class.report_unexpected_inconclusive!(
      screenshot: screenshot,
      reason: "capture_before_wallpaper_change"
    )
  end
end
