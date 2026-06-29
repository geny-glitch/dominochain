# frozen_string_literal: true

module Api
  class DevicesController < ApplicationController
    include ApiAuthenticatable

    def create
      device_id = params.require(:device_id)
      device = current_user.devices.find_or_initialize_by(device_id: device_id)
      device.auth_token = SecureRandom.hex(32)
      updates = {}
      updates[:screen_width] = params[:screen_width]&.to_i if params[:screen_width].present?
      updates[:screen_height] = params[:screen_height]&.to_i if params[:screen_height].present?
      updates[:fcm_token] = params[:fcm_token] if params[:fcm_token].present?
      updates[:name] = params[:name].presence if params.key?(:name)
      device.assign_attributes(updates)
      device.save!
      render json: {
        id: device.id,
        device_id: device.device_id,
        token: device.auth_token,
        web_url: wallpaper_upload_url(current_user.nickname)
      }
    end

    def wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.current_wallpaper

      if wallpaper&.image&.attached?
        wallpaper.update_column(:first_downloaded_at, Time.current) if wallpaper.first_downloaded_at.nil?
        image_url = device.screen_width.present? && device.screen_height.present? ?
          polymorphic_url(wallpaper.variant_for(device)) : polymorphic_url(wallpaper.image)
        render json: {
          url: image_url,
          updated_at: wallpaper.updated_at.iso8601
        }
      else
        head :not_found
      end
    end

    def upload_wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.wallpapers.create!(image: params[:image])
      device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current)
      url = device.screen_width.present? && device.screen_height.present? ?
        polymorphic_url(wallpaper.variant_for(device)) : polymorphic_url(wallpaper.image)
      render json: {
        id: wallpaper.id,
        url: url,
        updated_at: wallpaper.updated_at.iso8601
      }
    end

    def wallpapers
      device = Device.find_by!(device_id: params[:id])
      wallpapers = device.wallpapers.order(created_at: :desc)
      render json: wallpapers.map { |w|
        next unless w.image.attached?
        {
          id: w.id,
          url: device.screen_width.present? && device.screen_height.present? ?
            polymorphic_url(w.variant_for(device)) : polymorphic_url(w.image),
          created_at: w.created_at.iso8601,
          first_downloaded_at: w.first_downloaded_at&.iso8601
        }
      }.compact
    end

    def destroy_wallpaper
      device = Device.find_by!(device_id: params[:id])
      wallpaper = device.wallpapers.find(params[:wallpaper_id])
      wallpaper.destroy!
      head :no_content
    end

    def update_fcm_token
      device = Device.find_by!(device_id: params[:id])
      device.update!(fcm_token: params.require(:fcm_token))
      head :no_content
    end

    def update_name
      device = Device.find_by!(device_id: params[:id])
      device.update!(name: params[:name].presence)
      head :no_content
    end

    def update_permissions
      device = Device.find_by!(device_id: params[:id])
      missing = params[:permissions_missing]
      missing = missing.to_a.map(&:to_s) if missing.respond_to?(:to_a)
      permissions_ok = params.require(:permissions_ok)
      device.update!(
        permissions_ok: permissions_ok,
        permissions_missing: permissions_ok ? nil : (missing.presence&.to_json),
        permissions_checked_at: Time.current
      )
      head :no_content
    end

    def tasks
      device = Device.find_by!(device_id: params[:id])
      user = device.user
      return render json: [] unless user
      tasks = user.tasks.recent
      render json: tasks.map { |t| task_json(t) }
    end

    def task_detail
      device = Device.find_by!(device_id: params[:id])
      user = device.user
      return head :not_found unless user
      task = user.tasks.find(params[:task_id])
      render json: task_detail_json(task)
    end

    def screenshots
      device = current_device
      screenshots = device.device_screenshots.order(captured_at: :desc)
      render json: screenshots.map { |s|
        next unless s.image.attached?
        {
          id: s.id,
          url: url_for(s.image),
          captured_at: s.captured_at.iso8601
        }
      }.compact
    end

    def create_screenshot
      device = current_device
      return render json: { error: "Image requise" }, status: :unprocessable_entity if params[:image].blank?

      screenshot = device.device_screenshots.new(captured_at: Time.current, verification_status: "pending")
      screenshot.image.attach(params[:image])
      screenshot.save!

      enqueue_wallpaper_verification(screenshot.id)

      render json: {
        id: screenshot.id,
        url: url_for(screenshot.image),
        captured_at: screenshot.captured_at.iso8601
      }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    def submit_proof
      device = Device.find_by!(device_id: params[:id])
      user = device.user
      return head :not_found unless user
      task = user.tasks.find(params[:task_id])

      unless task.deadline_at.future?
        return render json: { error: "La deadline est dépassée" }, status: :unprocessable_entity
      end
      if task.proof_accepted?
        return render json: { error: "La preuve a déjà été acceptée" }, status: :unprocessable_entity
      end

      proof = task.proof_of_completion || task.build_proof_of_completion
      proof.text = params[:text].presence
      if params[:media].present?
        proof.media.purge if proof.media.attached?
        proof.media.attach(params[:media])
      end
      proof.status = "pending"
      proof.reviewed_at = nil
      proof.save!

      render json: { id: proof.id, status: proof.status }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    private

    def task_json(task)
      {
        id: task.id,
        name: task.name,
        description: task.description,
        expected_proof: task.expected_proof,
        deadline_at: task.deadline_at.iso8601,
        status: task.effective_status,
        can_submit_proof: task.can_submit_proof?,
        proof_status: task.proof_of_completion&.status
      }
    end

    def task_detail_json(task)
      json = task_json(task)
      if task.proof_of_completion.present?
        proof = task.proof_of_completion
        json[:proof] = {
          id: proof.id,
          text: proof.text,
          status: proof.status,
          review_comment: proof.review_comment,
          media_url: proof.media.attached? ? url_for(proof.media) : nil,
          created_at: proof.created_at.iso8601
        }
      else
        json[:proof] = nil
      end
      json[:punishments] = task.punishments.order(created_at: :desc).map { |p|
        {
          id: p.id,
          message: p.message,
          created_at: p.created_at.iso8601
        }
      }
      json
    end

    def wallpaper_upload_url(nickname)
      "#{request.base_url}/w/#{nickname}"
    end

    def enqueue_wallpaper_verification(screenshot_id)
      WallpaperVerificationJob.perform_later(screenshot_id)
    rescue SolidQueue::Job::EnqueueError, ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionFailed, PG::ConnectionBad => e
      Rails.logger.warn(
        "[Devices] Could not enqueue WallpaperVerificationJob screenshot=#{screenshot_id}: " \
        "#{e.class}: #{e.message}"
      )
    end
  end
end
