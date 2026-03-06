# frozen_string_literal: true

class Task < ApplicationRecord
  belongs_to :user
  has_one :proof_of_completion, dependent: :destroy
  has_many :punishments, dependent: :destroy

  default_scope { where(deleted_at: nil) }

  validates :name, presence: true
  validates :deadline_at, presence: true
  validates :status, inclusion: { in: %w[pending completed expired rejected] }

  scope :recent, -> { order(created_at: :desc) }

  after_create_commit :send_new_task_notification

  def expired?
    status == "expired" || (deadline_at.past? && status == "pending")
  end

  def effective_status
    (status == "pending" && deadline_at.past?) ? "expired" : status
  end

  def can_submit_proof?
    deadline_at.future? && !proof_accepted?
  end

  def proof_accepted?
    proof_of_completion&.accepted?
  end

  def proof_pending?
    proof_of_completion&.pending?
  end

  def soft_destroy!
    update_column(:deleted_at, Time.current)
  end

  private

  def send_new_task_notification
    user.devices.find_each do |device|
      FcmService.send_new_task_notification(device: device, task: self, trigger_alarm: trigger_alarm, alarm_sound: alarm_sound.presence || "urgent")
    end
  end
end
