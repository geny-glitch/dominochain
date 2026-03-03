# frozen_string_literal: true

class FcmService
  FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
  FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/%<project_id>s/messages:send"

  TEASER_MESSAGES = [
    "Ton univers a changé 👀",
    "Nouveau décor, nouvelle vibe",
    "Quelqu'un a mis à jour ton fond d'écran...",
    "Fais un tour, ton fond a été rafraîchi",
    "Pssst… ton fond d'écran a été mis à jour"
  ].freeze

  class << self
    def send_new_wallpaper_notification(device:)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped: credentials not configured. Set FIREBASE_PROJECT_ID and FIREBASE_CREDENTIALS_JSON on Fly.io."
        return
      end

      payload = {
        message: {
          token: device.fcm_token,
          data: { type: "new_wallpaper" },
          android: {
            priority: "high"
          }
        }
      }

      send_request(device, payload)
    end

    def send_teaser_notification(device:)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped teaser: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped teaser: credentials not configured."
        return
      end

      body = TEASER_MESSAGES.sample
      payload = {
        message: {
          token: device.fcm_token,
          notification: {
            title: "OTB",
            body: body
          },
          data: { type: "teaser" },
          android: {
            priority: "high"
          }
        }
      }

      send_request(device, payload)
    end

    def send_background_changed_notifications(device:)
      send_new_wallpaper_notification(device: device)
      send_teaser_notification(device: device)
    end

    def send_new_task_notification(device:, task:, trigger_alarm:, alarm_sound: "urgent")
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped new_task: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped new_task: credentials not configured."
        return
      end

      title = "OTB"
      body = "Nouvelle tâche : #{task.name}"

      # Data-only pour que onMessageReceived soit toujours appelé (même en background)
      # et qu'on puisse afficher la notif avec notre canal alarme
      data = {
        type: "new_task",
        task_id: task.id.to_s,
        trigger_alarm: trigger_alarm ? "true" : "false",
        alarm_sound: alarm_sound.presence || "urgent",
        title: title,
        body: body
      }

      payload = {
        message: {
          token: device.fcm_token,
          data: data,
          android: {
            priority: "high"
          }
        }
      }

      send_request(device, payload)
    end

    def send_proof_reviewed_notification(device:, proof:)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped proof_reviewed: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped proof_reviewed: credentials not configured."
        return
      end

      title = "OTB"
      body = proof.accepted? ? "Preuve acceptée ✓" : "Preuve refusée"
      body += ": #{proof.review_comment}" if proof.review_comment.present?

      payload = {
        message: {
          token: device.fcm_token,
          notification: { title: title, body: body },
          data: {
            type: "proof_reviewed",
            task_id: proof.task_id.to_s,
            status: proof.status,
            review_comment: proof.review_comment.to_s
          },
          android: { priority: "high" }
        }
      }

      send_request(device, payload)
    end

    def credentials_configured?
      project_id.present? && credentials_json.present?
    end

    private

    def send_request(device, payload)
      uri = URI(format(FCM_ENDPOINT, project_id: project_id))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{access_token}"
      request.body = payload.to_json

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        Rails.logger.info "[FCM] Push sent to device #{device.device_id}"
      else
        Rails.logger.error "[FCM] Failed to send push: #{response.code} #{response.body}"
        handle_failed_token(device, response) if response.code.to_i == 404 || response.code.to_i == 400
      end
    rescue StandardError => e
      Rails.logger.error "[FCM] Error sending push: #{e.message}"
    end

    def handle_failed_token(device, response)
      body = JSON.parse(response.body) rescue {}
      if body.dig("error", "details")&.any? { |d| d["errorCode"] == "UNREGISTERED" || d["errorCode"] == "INVALID_ARGUMENT" }
        device.update_column(:fcm_token, nil)
        Rails.logger.info "[FCM] Cleared invalid token for device #{device.device_id}"
      end
    end

    def access_token
      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(credentials_json),
        scope: FCM_SCOPE
      )
      credentials.fetch_access_token!["access_token"]
    end

    def project_id
      ENV["FIREBASE_PROJECT_ID"]
    end

    def credentials_json
      ENV["FIREBASE_CREDENTIALS_JSON"] || (path = ENV["FIREBASE_CREDENTIALS_PATH"]) && File.read(path)
    end
  end
end
