# frozen_string_literal: true

module LeveragePhotoPayload
  module_function

  def list_json(photos, helpers:)
    photos.map { |photo| summary_json(photo, helpers: helpers) }
  end

  def summary_json(photo, helpers:)
    preferred = photo.preferred_censored_attachment
    thumbnail = photo.thumbnail_attachment
    {
      id: photo.id,
      status: photo.status,
      locked_until: photo.locked_until&.iso8601,
      tlock_layer_count: photo.tlock_layer_count,
      original_filename: photo.original_filename,
      can_start_timer: photo.can_start_timer?,
      can_add_time: photo.can_add_time?,
      can_censor: photo.can_censor?,
      has_original: photo.original_image.attached?,
      has_censored: photo.censored_images.attached?,
      # Back-compat for Android clients that still read the old singular fields.
      has_teaser: photo.censored_images.attached?,
      teaser_url: attachment_url(thumbnail, helpers: helpers),
      censored_url: attachment_url(preferred, helpers: helpers),
      censored_images: censored_images_json(photo, helpers: helpers),
      created_at: photo.created_at.iso8601
    }
  end

  def detail_json(photo, helpers:)
    summary_json(photo, helpers: helpers).merge(
      initial_duration_seconds: photo.initial_duration_seconds,
      drand_rounds: photo.drand_rounds,
      wallpaper_ready: wallpaper_ready?(photo)
    )
  end

  def wallpaper_ready?(photo)
    user = photo.user
    return false if user.blank?
    return false unless BetaCatalog.new(user).source_enabled?("wallpaper")
    return false if user.devices.empty?
    return false if user.controlled_by_boss?
    return false if user.wallpaper_verification_session_locked?

    photo.censored_images.attached? || photo.original_image.attached?
  end

  def censored_images_json(photo, helpers:)
    return [] unless photo.censored_images.attached?

    photo.censored_images.map do |image|
      {
        id: image.id,
        url: attachment_url(image, helpers: helpers)
      }
    end
  end

  def attachment_url(attachment, helpers:)
    return nil if attachment.blank?
    return nil if attachment.respond_to?(:attached?) && !attachment.attached?

    helpers.rails_blob_url(attachment, only_path: false)
  rescue StandardError
    helpers.rails_blob_path(attachment, only_path: true)
  end
end
