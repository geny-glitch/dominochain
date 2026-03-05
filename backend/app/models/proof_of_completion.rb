# frozen_string_literal: true

class ProofOfCompletion < ApplicationRecord
  belongs_to :task

  has_one_attached :media

  validates :status, inclusion: { in: %w[pending accepted rejected] }
  validate :text_or_media_present

  after_update :send_proof_reviewed_notification_if_changed

  def accepted?
    status == "accepted"
  end

  def rejected?
    status == "rejected"
  end

  def pending?
    status == "pending"
  end

  private

  def text_or_media_present
    return if text.present? || media.attached?

    errors.add(:base, "La preuve doit contenir du texte ou une image/vidéo")
  end

  def send_proof_reviewed_notification_if_changed
    return unless saved_change_to_status?
    return unless accepted? || rejected?

    task.user.devices.find_each do |device|
      FcmService.send_proof_reviewed_notification(device: device, proof: self)
    end
  end
end
