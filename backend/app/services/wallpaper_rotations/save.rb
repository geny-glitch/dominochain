# frozen_string_literal: true

module WallpaperRotations
  class Save
    class Error < StandardError; end
    class NeedTwoPhotos < Error; end
    class TooManyPhotos < Error; end
    class InvalidInterval < Error; end

    def initialize(device:, enabled:, interval_seconds:, collages_enabled:, wallpaper_ids:)
      @device = device
      @enabled = enabled
      @interval_seconds = interval_seconds.to_i
      @collages_enabled = collages_enabled
      @wallpaper_ids = Array(wallpaper_ids)
    end

    def call
      ordered = ordered_wallpapers
      raise NeedTwoPhotos if @enabled && ordered.size < 2
      raise TooManyPhotos if @enabled && ordered.size > Schedule::MAX_PHOTOS
      raise InvalidInterval unless @interval_seconds.between?(Schedule::MIN_INTERVAL_SECONDS, Schedule::MAX_INTERVAL_SECONDS)

      playlist = @device.wallpaper_playlist || @device.build_wallpaper_playlist
      ActiveRecord::Base.transaction do
        playlist.update!(
          enabled: @enabled && ordered.size >= 2,
          interval_seconds: @interval_seconds,
          collages_enabled: @collages_enabled,
          anchor_at: Time.current
        )
        playlist.items.destroy_all
        ordered.each_with_index do |wallpaper, index|
          playlist.items.create!(wallpaper: wallpaper, position: index)
        end
        playlist.touch
      end

      FcmService.send_background_changed_notifications(device: @device)
      playlist
    end

    private

    def ordered_wallpapers
      ids = @wallpaper_ids.map(&:to_i).uniq.reject(&:zero?)
      found = @device.wallpapers.where(id: ids).index_by(&:id)
      ids.filter_map { |id| found[id] }
    end
  end
end
