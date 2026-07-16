# frozen_string_literal: true

class LeveragePhotos::AddTime
  class Error < StandardError; end

  def initialize(photo:, tlock_blob:, drand_round:, locked_until:, added_seconds:)
    @photo = photo
    @tlock_blob = tlock_blob
    @drand_round = drand_round.to_i
    @locked_until = locked_until
    @added_seconds = added_seconds.to_i
  end

  def call!
    raise Error, "cannot add time" unless @photo.can_add_time?
    raise Error, "tlock blob missing" if @tlock_blob.blank?
    raise Error, "invalid round" if @drand_round <= 0
    raise Error, "invalid locked_until" if @locked_until.blank? || @locked_until <= @photo.locked_until
    raise Error, "invalid added_seconds" if @added_seconds <= 0

    previous_rounds = Array(@photo.drand_rounds)
    raise Error, "round must be later" if previous_rounds.any? && @drand_round <= previous_rounds.last.to_i

    locked_until_before = @photo.locked_until

    LeveragePhoto.transaction do
      @photo.tlock_blob.purge
      @photo.tlock_blob.attach(@tlock_blob)
      @photo.leverage_photo_extensions.create!(
        added_seconds: @added_seconds,
        locked_until_before: locked_until_before,
        locked_until_after: @locked_until,
        drand_round_added: @drand_round
      )
      @photo.update!(
        locked_until: @locked_until,
        drand_rounds: previous_rounds + [@drand_round],
        tlock_layer_count: @photo.tlock_layer_count + 1
      )
    end

    @photo
  end
end
