# frozen_string_literal: true

class PublicBossController < ApplicationController
  def show
    @beta = User.find_by(nickname: params[:nickname], role: :beta)
    return render "showcase/not_found", status: :not_found unless @beta&.public_boss_enabled?

    @nickname = @beta.nickname
    @devices = @beta.devices.order(created_at: :desc)
    @device = @devices.first
    @device_id = @device&.device_id
    @read_only = true

    load_boss_dashboard_data if @device
    render "wallpaper/show"
  end

  private

  def load_boss_dashboard_data
    @applications = @device.wallpaper_applications
      .includes(wallpaper: { image_attachment: { blob: { variant_records: { image_attachment: :blob } } } })
      .recent
    @tasks = @beta.tasks.recent
    @screenshots = @device.device_screenshots
      .includes(image_attachment: { blob: { variant_records: { image_attachment: :blob } } })
      .order(captured_at: :desc)
    @latest_screenshot = @screenshots.first
  end
end
