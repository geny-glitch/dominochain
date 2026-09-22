# frozen_string_literal: true

class LeveragePhoto < ApplicationRecord
  STATUSES = %w[draft active unlocked sanctioned deleted].freeze
  TLOCK_FORMAT_FULL_IMAGE = "full_image"
  TLOCK_FORMAT_ENVELOPE = "envelope"
  TLOCK_FORMATS = [TLOCK_FORMAT_FULL_IMAGE, TLOCK_FORMAT_ENVELOPE].freeze
  MAX_TLOCK_LAYERS = 20
  # Restore peels until plaintext, not until tlock_layer_count. The recorded
  # count can lag the real onion (server relock wraps without resetting it).
  MAX_PEEL_LAYERS = 64
  MAX_DURATION_SECONDS = 365.days.to_i
  MIN_DURATION_SECONDS = 1.minute.to_i
  DURATION_UNIT_SECONDS = {
    "years" => 365.days.to_i,
    "months" => 30.days.to_i,
    "weeks" => 7.days.to_i,
    "days" => 1.day.to_i,
    "hours" => 1.hour.to_i,
    "minutes" => 1.minute.to_i
  }.freeze
  DURATION_UNIT_KEYS = %w[years months weeks days hours minutes].freeze
  # drand quicknet (mainnetClient in tlock-js)
  DEFAULT_DRAND_CHAIN_HASH = "52db9ba70e0cc0f6eaf7803dd07447a1f5477735fd3f661792ba94600c84e971"

  belongs_to :user
  belongs_to :bundle, class_name: "LeveragePhotoBundle", inverse_of: :leverage_photos
  has_many :leverage_photo_extensions, dependent: :destroy
  has_many :wallpapers, dependent: :nullify

  has_one_attached :original_image
  has_many_attached :censored_images
  has_one_attached :tlock_blob
  has_one_attached :encrypted_original

  validates :status, inclusion: { in: STATUSES }
  validates :tlock_format, inclusion: { in: TLOCK_FORMATS }
  validate :attachments_match_status, on: :strict

  before_validation :ensure_bundle, on: :create

  LIST_SORT_DEFAULT = "unlock_asc"
  LIST_SORT_KEYS = %w[unlock_asc unlock_desc newest].freeze
  NULLS_LAST = Arel.sql("CASE WHEN locked_until IS NULL THEN 1 ELSE 0 END ASC").freeze

  scope :not_deleted, -> { where.not(status: "deleted") }
  scope :active, -> { where(status: "active") }
  scope :due_for_unlock, ->(at = Time.current) { active.where("locked_until <= ?", at) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :by_unlock_asc, -> { order(NULLS_LAST, locked_until: :asc, created_at: :desc) }
  scope :by_unlock_desc, -> { order(NULLS_LAST, locked_until: :desc, created_at: :desc) }

  def self.normalize_list_sort(sort)
    key = sort.to_s
    LIST_SORT_KEYS.include?(key) ? key : LIST_SORT_DEFAULT
  end

  def self.apply_list_sort(scope, sort)
    case normalize_list_sort(sort)
    when "unlock_desc" then scope.by_unlock_desc
    when "newest" then scope.newest_first
    else scope.by_unlock_asc
    end
  end

  def self.for_user_list(user, sort: LIST_SORT_DEFAULT)
    photos = user.leverage_photos.not_deleted.with_attached_censored_images.includes(:bundle)
    grouped = photos.group_by { |photo| photo.bundle_id || photo.id }
    covers = grouped.map do |_key, members|
      cover = members.min_by { |photo| [photo.position.to_i, photo.id] }
      cover.instance_variable_set(
        :@bundle_mates,
        members.sort_by { |photo| [photo.position.to_i, photo.id] }
      )
      cover
    end

    case normalize_list_sort(sort)
    when "unlock_desc"
      covers.sort_by { |photo| [photo.locked_until ? 0 : 1, -(photo.locked_until || Time.zone.at(0)).to_i, -photo.created_at.to_i] }
    when "newest"
      covers.sort_by { |photo| -photo.bundle_mates.map(&:created_at).max.to_i }
    else
      covers.sort_by { |photo| [photo.locked_until ? 0 : 1, photo.locked_until || Time.zone.at(0), photo.created_at] }
    end
  end

  def self.uploaded_files(*values)
    Array.wrap(values).flatten.select do |file|
      file.respond_to?(:original_filename) && file.original_filename.present?
    end
  end

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

  def bundle_mates
    return @bundle_mates if defined?(@bundle_mates) && @bundle_mates

    if bundle
      bundle.leverage_photos.not_deleted.order(:position, :id).to_a
    else
      [self]
    end
  end

  def bundle_lock_targets
    bundle_mates.reject { |photo| photo.deleted? || photo.sanctioned? }
  end

  def bundle_can_start_timer?
    targets = bundle_lock_targets
    targets.any? && targets.all?(&:can_start_timer?)
  end

  def bundle_can_add_time?
    targets = bundle_lock_targets
    targets.any? && targets.all?(&:can_add_time?)
  end

  def timer_photo
    mates = bundle_mates
    mates.find(&:active?) || mates.find(&:unlocked?) || mates.find(&:draft?) || mates.first
  end

  def bundle_display_name
    mates = bundle_mates
    return download_filename if mates.size <= 1

    I18n.t("leverage_photo.bundle.photo_count", count: mates.size)
  end

  def mosaic_photos
    bundle_mates.first(4)
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

  def sanctioned?
    status == "sanctioned"
  end

  def deleted?
    status == "deleted"
  end

  def envelope_lock?
    tlock_format == TLOCK_FORMAT_ENVELOPE
  end

  def full_image_lock?
    tlock_format == TLOCK_FORMAT_FULL_IMAGE
  end

  def needs_legacy_client_peel?
    unlocked? && full_image_lock? && tlock_blob.attached? && !viewable_original?
  end

  def viewable_original?
    return false unless original_image.attached?

    original_image.open do |file|
      !self.class.envelope_key_payload?(file.read(64))
    end
  rescue ActiveStorage::FileNotFoundError
    false
  end

  def self.image_magic?(bytes)
    head = bytes.to_s.byteslice(0, 12).to_s.b
    head.start_with?("\xFF\xD8\xFF".b) || head.start_with?("\x89PNG".b)
  end

  def self.envelope_key_payload?(bytes)
    text = bytes.to_s.lstrip
    text.start_with?("{") && text.include?('"alg":"aes-256-gcm"')
  end

  def ready_to_lock?
    draft? && original_image.attached? && censored_images.attached?
  end

  def ready_to_relock?
    unlocked? && censored_images.attached? && (viewable_original? || tlock_blob.attached?)
  end

  def can_start_timer?
    ready_to_lock? || ready_to_relock?
  end

  def can_censor?
    return false unless draft? || unlocked?
    return original_image.attached? if draft?

    viewable_original?
  end

  def can_attach_censored?
    !deleted?
  end

  def needs_censor?
    can_censor? && !censored_images.attached?
  end

  def can_add_time?
    return false unless active? && tlock_blob.attached?
    return true if full_image_lock?

    tlock_layer_count < MAX_TLOCK_LAYERS
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

  def eligible_for_sanction_delete?
    can_delete_original?
  end

  # Crop keeps existing censored versions, adds a puzzled board, and removes the original.
  def eligible_for_crop_to_progress?
    return false if deleted?

    original_image.attached? || tlock_blob.attached? || censored_images.attached?
  end

  def can_delete_original?
    return false if deleted? || sanctioned?
    return false unless censored_images.attached?

    original_image.attached? || tlock_blob.attached?
  end

  def unlock_due?(at = Time.current)
    active? && locked_until.present? && locked_until <= at
  end

  def mark_unlocked!
    update!(status: "unlocked")
    LeveragePhotos::SyncLinkedWallpapers.on_unlocked!(self)
  end

  def persist_restored_original!(uploaded_original)
    bytes, attachable = read_restored_original(uploaded_original)
    raise ArgumentError, "original is not an image" if self.class.envelope_key_payload?(bytes)

    filename = download_filename
    tlock_blob.purge if tlock_blob.attached?
    encrypted_original.purge if encrypted_original.attached?
    original_image.attach(attachable)
    original_image.blob.update!(filename: filename) if original_image.attached?
    save!
    assert_attachments!
  end

  def delete_original_from_sanction!
    was_active = active?
    was_unlocked = unlocked?

    original_image.purge if original_image.attached?
    tlock_blob.purge if tlock_blob.attached?
    encrypted_original.purge if encrypted_original.attached?
    leverage_photo_extensions.destroy_all
    update!(
      status: "sanctioned",
      locked_until: nil,
      drand_rounds: [],
      tlock_layer_count: 0,
      drand_chain_hash: nil,
      tlock_format: TLOCK_FORMAT_FULL_IMAGE,
      initial_duration_seconds: nil,
      add_time_base_seconds: nil,
      add_time_step_n: 0
    )
    assert_attachments!

    if was_active || was_unlocked
      LeveragePhotos::SyncLinkedWallpapers.on_locking!(self)
    end
  end

  # Highest-definition censored version (largest blob). Use this on lists and as
  # the locked hero — mixed uploads may include a tiny preview plus a full reminder.
  # Returns an ActiveStorage::Attachment (not Attached::One) — use .present?, not .attached?.
  def preferred_censored_attachment
    return nil unless censored_images.attached?

    censored_images.max_by { |image| image.blob.byte_size }
  end

  # Smallest censored version. Wallpaper teaser / compact API preview only.
  # Returns an ActiveStorage::Attachment (not Attached::One) — use .present?, not .attached?.
  def thumbnail_attachment
    return nil unless censored_images.attached?

    censored_images.min_by { |image| image.blob.byte_size }
  end

  # Initial lock plus add-time rows for the current timer (cleared on relock).
  def current_lock_time_entries
    rows = []
    started = initial_duration_seconds.to_i
    rows << { kind: :started, seconds: started } if started.positive?
    leverage_photo_extensions.sort_by(&:created_at).each do |extension|
      rows << { kind: :added, seconds: extension.added_seconds, at: extension.created_at }
    end
    rows
  end

  def current_lock_total_seconds
    initial_duration_seconds.to_i + leverage_photo_extensions.sum { |extension| extension.added_seconds.to_i }
  end

  def add_time_base?
    add_time_base_seconds.to_i.positive?
  end

  def next_step_n
    add_time_step_n.to_i + 1
  end

  def next_step_seconds
    return nil unless add_time_base?

    next_step_n * add_time_base_seconds
  end

  def self.duration_parts(seconds)
    seconds = seconds.to_i
    DURATION_UNIT_KEYS.each do |unit|
      unit_seconds = DURATION_UNIT_SECONDS.fetch(unit)
      next if seconds < unit_seconds
      next unless (seconds % unit_seconds).zero?

      return [seconds / unit_seconds, unit]
    end

    [[(seconds / 60.0).round, 1].max, "minutes"]
  end

  def self.max_amount_for_unit(unit)
    unit_seconds = DURATION_UNIT_SECONDS[unit]
    return MAX_DURATION_SECONDS / 60 if unit_seconds.blank?

    [MAX_DURATION_SECONDS / unit_seconds, 1].max
  end

  # Original when available, otherwise preferred censored.
  # May return Attached::One or ActiveStorage::Attachment — use .present?, not .attached?.
  def wallpaper_display_attachment
    if viewable_original?
      original_image
    else
      preferred_censored_attachment
    end
  end

  # May return ActiveStorage::Attachment — use .present?, not .attached?.
  def wallpaper_locked_attachment
    preferred_censored_attachment
  end

  def permanently_delete!
    original_image.purge if original_image.attached?
    censored_images.purge if censored_images.attached?
    tlock_blob.purge if tlock_blob.attached?
    encrypted_original.purge if encrypted_original.attached?
    update!(
      status: "deleted",
      locked_until: nil,
      drand_rounds: [],
      tlock_layer_count: 0,
      drand_chain_hash: nil,
      tlock_format: TLOCK_FORMAT_FULL_IMAGE,
      initial_duration_seconds: nil,
      add_time_base_seconds: nil,
      add_time_step_n: 0,
      original_filename: nil
    )
  end

  def assert_attachments!
    valid?(:strict) || raise(ActiveRecord::RecordInvalid, self)
  end

  private

  def ensure_bundle
    return if bundle.present? || user.blank?

    self.bundle = user.leverage_photo_bundles.build
    self.position ||= 0
  end

  def read_restored_original(uploaded_original)
    if uploaded_original.is_a?(Hash) && uploaded_original[:io]
      io = uploaded_original[:io]
      io.rewind if io.respond_to?(:rewind)
      bytes = io.read
      io.rewind if io.respond_to?(:rewind)
      [bytes, uploaded_original]
    elsif uploaded_original.respond_to?(:read)
      uploaded_original.rewind if uploaded_original.respond_to?(:rewind)
      bytes = uploaded_original.read
      uploaded_original.rewind if uploaded_original.respond_to?(:rewind)
      [bytes, uploaded_original]
    else
      raise ArgumentError, "original missing"
    end
  end

  def attachments_match_status
    case status
    when "draft"
      errors.add(:original_image, :blank) unless original_image.attached?
      errors.add(:censored_images, :blank) unless censored_images.attached?
    when "active"
      errors.add(:original_image, "must be purged while locked") if original_image.attached?
      errors.add(:tlock_blob, :blank) unless tlock_blob.attached?
      errors.add(:censored_images, :blank) unless censored_images.attached?
      if envelope_lock?
        errors.add(:encrypted_original, :blank) unless encrypted_original.attached?
      elsif encrypted_original.attached?
        errors.add(:encrypted_original, "must be absent for full-image locks")
      end
    when "unlocked"
      errors.add(:censored_images, :blank) unless censored_images.attached?
      unless original_image.attached? || tlock_blob.attached?
        errors.add(:base, "must have original or locked payload while unlocked")
      end
      if envelope_lock? && tlock_blob.attached? && !original_image.attached? && !encrypted_original.attached?
        errors.add(:encrypted_original, :blank)
      end
    when "sanctioned"
      errors.add(:original_image, "must be purged after sanction delete") if original_image.attached?
      errors.add(:tlock_blob, "must be purged after sanction delete") if tlock_blob.attached?
      errors.add(:encrypted_original, "must be purged after sanction delete") if encrypted_original.attached?
      errors.add(:censored_images, :blank) unless censored_images.attached?
    end
  end
end
