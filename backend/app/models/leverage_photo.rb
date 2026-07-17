# frozen_string_literal: true

class LeveragePhoto < ApplicationRecord
  STATUSES = %w[draft active unlocked deleted].freeze
  MAX_TLOCK_LAYERS = 20
  MAX_DURATION_SECONDS = 365.days.to_i
  MIN_DURATION_SECONDS = 1.minute.to_i
  # drand quicknet (mainnetClient in tlock-js)
  DEFAULT_DRAND_CHAIN_HASH = "52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971"

  belongs_to :user
  has_many :leverage_photo_extensions, dependent: :destroy
  has_many :wallpapers, dependent: :nullify

  has_one_attached :original_image
  has_one_attached :censored_image
  has_one_attached :teaser_image
  has_one_attached :tlock_blob

  validates :status, inclusion: { in: STATUSES }
  validate :attachments_match_status, on: :strict

  scope :not_deleted, -> { where.not(status: "deleted") }
  scope :active, -> { where(status: "active") }
  scope :due_for_unlock, ->(at = Time.current) { active.where("locked_until <= ?", at) }
  scope :newest_first, -> { order(created_at: :desc) }

  def self.normalized_original_filename(name)
    base = File.basename(name.to_s.strip)
    return "photo.jpg" if base.blank?

    stem = File.basename(base, ".*")
    stem = "photo" if stem.blank?
    "#{stem}.jpg"
  end

  def download_filename
    original_filename.presence || "photo.jpg"
  end

  def draft?
    status == "draft"
  end

  def active?
    status == "active"
  end

  def unlocked?
    status == "unlocked"
  end

  def deleted?
    status == "deleted"
  end

  def ready_to_lock?
    draft? && original_image.attached? && teaser_image.attached?
  end

  def ready_to_relock?
    unlocked? && teaser_image.attached? && tlock_blob.attached?
  end

  def can_start_timer?
    ready_to_lock? || ready_to_relock?
  end

  def can_censor?
    draft? && original_image.attached?
  end

  def needs_censor?
    can_censor? && !censored_image.attached?
  end

  def can_add_time?
    active? && tlock_blob.attached? && tlock_layer_count < MAX_TLOCK_LAYERS
  end

  def eligible_for_start?
    ready_to_lock?
  end

  def eligible_for_add_time?
    can_add_time?
  end

  def eligible_for_lock?
    can_start_timer? || can_add_time?
  end

  def eligible_for_delete?
    !deleted?
  end

  def unlock_due?(at = Time.current)
    active? && locked_until.present? && locked_until <= at
  end

  def mark_unlocked!
    update!(status: "unlocked")
    LeveragePhotos::SyncLinkedWallpapers.on_unlocked!(self)
  end

  def wallpaper_display_attachment
    if original_image.attached?
      original_image
    elsif censored_image.attached?
      censored_image
    elsif teaser_image.attached?
      teaser_image
    end
  end

  def wallpaper_locked_attachment
    if censored_image.attached?
      censored_image
    elsif teaser_image.attached?
      teaser_image
    end
  end

  def permanently_delete!
    original_image.purge if original_image.attached?
    censored_image.purge if censored_image.attached?
    teaser_image.purge if teaser_image.attached?
    tlock_blob.purge if tlock_blob.attached?
    update!(
      status: "deleted",
      locked_until: nil,
      drand_rounds: [],
      tlock_layer_count: 0,
      drand_chain_hash: nil,
      initial_duration_seconds: nil,
      original_filename: nil
    )
  end

  def assert_attachments!
    valid?(:strict) || raise(ActiveRecord::RecordInvalid, self)
  end

  private

  def attachments_match_status
    case status
    when "draft"
      errors.add(:original_image, :blank) unless original_image.attached?
      errors.add(:teaser_image, :blank) unless teaser_image.attached?
    when "active", "unlocked"
      errors.add(:original_image, "must be purged after timer start") if original_image.attached?
      errors.add(:tlock_blob, :blank) unless tlock_blob.attached?
      errors.add(:teaser_image, :blank) unless teaser_image.attached?
    end
  end
end
