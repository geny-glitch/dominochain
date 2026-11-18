# frozen_string_literal: true

module WallpaperRotations
  # Slot clock shared with the Android rotator.
  # Collage slots are those where slot % COLLAGE_STRIDE == COLLAGE_STRIDE - 1
  # (about one change in five). A collage uses 4 photos on even slots when at
  # least 4 photos are selected, otherwise 2. Indexes walk forward from the slot.
  module Schedule
    COLLAGE_STRIDE = 5
    MIN_INTERVAL_SECONDS = 10
    MAX_INTERVAL_SECONDS = 24.hours.to_i
    MAX_PHOTOS = 24

    module_function

    def slot_index(anchor_at:, interval_seconds:, at:)
      elapsed = at.to_i - anchor_at.to_i
      elapsed = 0 if elapsed.negative?
      elapsed / interval_seconds
    end

    def collage?(slot:, count:, collages_enabled:)
      collages_enabled && count >= 2 && (slot % COLLAGE_STRIDE) == (COLLAGE_STRIDE - 1)
    end

    def indexes(slot:, count:, collage:)
      return [] if count <= 0
      return [slot % count] unless collage

      cell_count = count >= 4 && slot.even? ? 4 : 2
      Array.new(cell_count) { |offset| (slot + offset) % count }
    end
  end
end
