# frozen_string_literal: true

module WallpaperRotations
  # The background that should be on screen at a given time.
  class Frame
    def self.for(device:, at:)
      playlist = device.wallpaper_playlist
      return nil unless playlist&.active?
      return nil if at < playlist.anchor_at

      new(playlist, at)
    end

    def initialize(playlist, at)
      @playlist = playlist
      @at = at
      @wallpapers = playlist.ordered_wallpapers
      @slot = Schedule.slot_index(
        anchor_at: playlist.anchor_at,
        interval_seconds: playlist.interval_seconds,
        at: at
      )
    end

    def collage?
      Schedule.collage?(
        slot: @slot,
        count: @wallpapers.size,
        collages_enabled: @playlist.collages_enabled?
      )
    end

    def indexes
      Schedule.indexes(slot: @slot, count: @wallpapers.size, collage: collage?)
    end

    def wallpapers_for_slot
      indexes.map { |index| @wallpapers[index] }
    end

    def primary_wallpaper
      wallpapers_for_slot.first
    end

    def render
      Collage.render(wallpapers: wallpapers_for_slot, device: @playlist.device)
    end

    def to_jpeg(image = render)
      Collage.to_jpeg(image)
    end
  end
end
