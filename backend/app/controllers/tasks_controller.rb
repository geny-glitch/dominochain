# frozen_string_literal: true

class TasksController < ApplicationController
  include BetaAccessControl
  before_action :set_task, only: [:show, :review_proof, :punish, :destroy]

  def create
    deadline_at = compute_deadline
    @task = @beta.tasks.create!(task_params.merge(deadline_at: deadline_at))
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.tasks.created")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: e.record.errors.full_messages.join(", ")
  rescue ArgumentError => e
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: e.message
  end

  def show
    # Rendered for boss to review proof
  end

  def review_proof
    unless @task.proof_of_completion&.pending?
      redirect_to wallpaper_task_path(@nickname, @task), alert: t("flash.tasks.no_pending_proof")
      return
    end

    accept = params[:decision] == "accept"
    proof = @task.proof_of_completion
    proof.update!(status: accept ? "accepted" : "rejected", reviewed_at: Time.current, review_comment: params[:review_comment].presence)
    @task.update!(status: accept ? "completed" : "rejected")

    if accept
      redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.tasks.proof_accepted")
    else
      redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.tasks.proof_rejected")
    end
  end

  def punish
    unless @task.expired?
      redirect_to wallpaper_task_path(@nickname, @task, device_id: @device_id), alert: t("flash.tasks.punish_only_expired")
      return
    end

    @task.update!(status: "expired") if @task.status == "pending"

    message = params[:punishment_message].presence
    @task.punishments.create!(message: message)

    @task.user.devices.find_each do |device|
      FcmService.send_punishment_notification(device: device, task: @task, message: message)
    end

    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.tasks.punish_sent")
  end

  def destroy
    @task.soft_destroy!
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), notice: t("flash.tasks.deleted")
  end

  private

  def set_task
    @task = @beta.tasks.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to wallpaper_upload_path(@nickname, device_id: @device_id), alert: t("flash.tasks.not_found")
  end

  def task_params
    params.require(:task).permit(:name, :description, :expected_proof, :trigger_alarm, :alarm_sound)
  end

  def compute_deadline
    if params[:deadline_mode] == "duration"
      duration_minutes = params[:deadline_duration].to_i
      Time.current + duration_minutes.minutes
    else
      raw = params.dig(:task, :deadline_at)
      raw.present? ? Time.zone.parse(raw) : raise(ArgumentError, I18n.t("flash.tasks.deadline_required"))
    end
  end
end
