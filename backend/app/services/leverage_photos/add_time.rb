# frozen_string_literal: true

class LeveragePhotos::AddTime
  class Error < StandardError; end

  def initialize(photo:, tlock_blob:, drand_round:, locked_until:, added_seconds:, save_as_base: false, apply_next_step: false, tlock_format: nil, tlock_layer_count: nil, encrypted_original: nil)
    @photo = photo
    @tlock_blob = tlock_blob
    @drand_round = drand_round.to_i
    @locked_until = locked_until
    @added_seconds = added_seconds.to_i
    @save_as_base = save_as_base
    @apply_next_step = apply_next_step
    @tlock_format = tlock_format
    @tlock_layer_count = tlock_layer_count
    @encrypted_original = encrypted_original
  end

  def call!
    raise Error, "tlock blob missing" if @tlock_blob.blank?
    raise Error, "invalid round" if @drand_round <= 0
    raise Error, "invalid added_seconds" if @added_seconds <= 0

    # Serialize with StartTimer and other extends. A stale wrap of an older
    # blob is rejected via locked_until / drand round after the first commit.
    @photo.with_lock do
      raise Error, "cannot add time" unless @photo.can_add_time?
      raise Error, "invalid locked_until" if @locked_until.blank? || @locked_until <= @photo.locked_until

      previous_rounds = Array(@photo.drand_rounds)
      raise Error, "round must be later" if previous_rounds.any? && @drand_round <= previous_rounds.last.to_i

      locked_until_before = @photo.locked_until

      attach_encrypted_original!
      @photo.tlock_blob.purge
      @photo.tlock_blob.attach(@tlock_blob)
      @photo.leverage_photo_extensions.create!(
        added_seconds: @added_seconds,
        locked_until_before: locked_until_before,
        locked_until_after: @locked_until,
        drand_round_added: @drand_round
      )
      attrs = {
        locked_until: @locked_until,
        drand_rounds: previous_rounds + [@drand_round],
        tlock_layer_count: @tlock_layer_count.nil? ? (@photo.tlock_layer_count + 1) : @tlock_layer_count.to_i
      }
      attrs[:tlock_format] = @tlock_format if @tlock_format.present?
      if @save_as_base || (@apply_next_step && !@photo.add_time_base?)
        attrs[:add_time_base_seconds] = @added_seconds
        attrs[:add_time_step_n] = 1
      elsif @apply_next_step
        attrs[:add_time_step_n] = @photo.add_time_step_n.to_i + 1
      end
      @photo.update!(attrs)
    end

    @photo
  end

  private

  def attach_encrypted_original!
    return if @encrypted_original.blank?

    @photo.encrypted_original.purge if @photo.encrypted_original.attached?
    @photo.encrypted_original.attach(@encrypted_original)
  end
end
