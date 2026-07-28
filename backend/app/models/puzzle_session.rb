# frozen_string_literal: true

class PuzzleSession < ApplicationRecord
  STATUSES = %w[assigned active completed failed_time abandoned].freeze
  OPEN_STATUSES = %w[assigned active].freeze
  ORIGINS = %w[self scenario].freeze
  IMAGE_SOURCES = %w[leverage_photo wallpaper upload].freeze
  REFERENCE_MODES = PuzzleConfig::REFERENCE_MODES
  MAX_PUZZLE_IMAGE_SIDE = 1200

  belongs_to :user
  belongs_to :leverage_photo, optional: true
  belongs_to :wallpaper, optional: true
  has_many :puzzle_session_events, dependent: :destroy
  has_one_attached :upload_image
  has_one_attached :progress_snapshot

  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :image_source, inclusion: { in: IMAGE_SOURCES }
  validates :reference_mode, inclusion: { in: REFERENCE_MODES }
  validates :piece_count,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: PuzzleConfig::MIN_PIECE_COUNT,
      less_than_or_equal_to: PuzzleConfig::MAX_PIECE_COUNT
    }
  validates :grid_cols, :grid_rows, :pieces_total, :layout_seed,
    numericality: { only_integer: true, greater_than: 0 }
  validates :pieces_placed,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :image_source_attachments_present
  validate :pieces_placed_within_total

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :open, -> { where(status: OPEN_STATUSES) }

  def open?
    OPEN_STATUSES.include?(status)
  end

  def assigned?
    status == "assigned"
  end

  def active?
    status == "active"
  end

  def terminal?
    !open?
  end

  def display_attachment
    case image_source
    when "leverage_photo"
      leverage_photo&.wallpaper_display_attachment
    when "wallpaper"
      wallpaper&.image
    when "upload"
      upload_image if upload_image.attached?
    end
  end

  def display_attachment_present?
    attachment = display_attachment
    attachment.respond_to?(:attached?) ? attachment.attached? : attachment.present?
  end

  def mark_active!
    now = Time.current
    attrs = { status: "active", started_at: now }
    if time_limit_seconds.present? && time_limit_seconds.positive?
      attrs[:deadline_at] = now + time_limit_seconds.seconds
    end
    update!(attrs)
  end

  def past_deadline?(at: Time.current)
    deadline_at.present? && at >= deadline_at
  end

  def completed_in_time?(at: Time.current)
    return true if deadline_at.blank?

    at < deadline_at
  end

  private

  def image_source_attachments_present
    case image_source
    when "leverage_photo"
      errors.add(:leverage_photo, :blank) if leverage_photo_id.blank?
    when "wallpaper"
      errors.add(:wallpaper, :blank) if wallpaper_id.blank?
    when "upload"
      errors.add(:upload_image, :blank) unless upload_image.attached?
    end
  end

  def pieces_placed_within_total
    return if pieces_total.blank? || pieces_placed.blank?
    return if pieces_placed <= pieces_total

    errors.add(:pieces_placed, :invalid)
  end
end
