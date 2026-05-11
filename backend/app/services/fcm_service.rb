# frozen_string_literal: true

class FcmService
  FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
  FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/%<project_id>s/messages:send"
  NOTIFICATION_TITLE_STAGING = "Domino Chain dev"
  NOTIFICATION_TITLE_DEFAULT = "Domino Chain"

  TEASER_MESSAGES = [
    "Ton univers a changé 👀",
    "Nouveau décor, nouvelle vibe",
    "Quelqu'un a mis à jour ton fond d'écran...",
    "Fais un tour, ton fond a été rafraîchi",
    "Pssst… ton fond d'écran a été mis à jour"
  ].freeze

  SCREENSHOT_TEASER_MESSAGES = [
    "On vérifie ton écran 📸",
    "Capture en cours...",
    "Vérification en direct",
    "Ton écran est en cours de capture"
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
            title: notification_title,
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

    def send_background_changed_notifications_to_devices(devices:)
      devices.each { |d| send_background_changed_notifications(device: d) }
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

      title = notification_title
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

    def send_take_screenshot_notification(device:)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped take_screenshot: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped take_screenshot: credentials not configured."
        return
      end

      body = SCREENSHOT_TEASER_MESSAGES.sample
      # Data-only pour que onMessageReceived soit toujours appelé (même en background)
      # et qu'on puisse afficher la notif teaser + déclencher la capture
      data = {
        type: "take_screenshot",
        title: notification_title,
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

    def send_grant_permissions_notification(device:)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped grant_permissions: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped grant_permissions: credentials not configured."
        return
      end

      data = {
        type: "grant_permissions",
        title: notification_title,
        body: "Accorde les autorisations nécessaires pour que l'app fonctionne correctement"
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

      title = notification_title
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

    def send_showcase_game_notification(device:, player_name:, score:, game_type:)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped showcase_game: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped showcase_game: credentials not configured."
        return
      end

      label = showcase_game_label(game_type)
      title = notification_title
      body = "#{player_name} a terminé une partie de #{label} : #{score} point#{'s' if score != 1}"

      payload = {
        message: {
          token: device.fcm_token,
          notification: { title: title, body: body },
          data: {
            type: "showcase_game",
            player_name: player_name.to_s,
            score: score.to_s,
            game_type: game_type.to_s
          },
          android: { priority: "high" }
        }
      }

      send_request(device, payload)
    end

    def send_showcase_game_started_notification(device:, game_session_id:, game_type:, player_name: nil)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped showcase_game_started: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped showcase_game_started: credentials not configured."
        return
      end

      label = showcase_game_label(game_type)
      title = notification_title
      starter_name = player_name.to_s.squish
      body = if starter_name.present?
        "#{starter_name} commence une partie de #{label}."
      else
        "Quelqu'un commence une partie de #{label}."
      end
      data = {
        type: "showcase_game_started",
        game_session_id: game_session_id.to_s,
        game_type: game_type.to_s
      }
      data[:player_name] = starter_name if starter_name.present?

      payload = {
        message: {
          token: device.fcm_token,
          notification: { title: title, body: body },
          data: data,
          android: { priority: "high" }
        }
      }

      send_request(device, payload)
    end

    def send_showcase_backdoor_notification(device:, player_name:, seconds:, message:)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped showcase_backdoor: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped showcase_backdoor: credentials not configured."
        return
      end

      label = format_duration_for_notification(seconds)
      body = "#{player_name} a ajouté #{label} sur la vitrine."
      body += " « #{message.truncate(180)} »"

      payload = {
        message: {
          token: device.fcm_token,
          notification: { title: notification_title, body: body },
          data: {
            type: "showcase_backdoor",
            player_name: player_name.to_s,
            seconds: seconds.to_s,
            message: message.to_s
          },
          android: { priority: "high" }
        }
      }

      send_request(device, payload)
    end

    def send_punishment_notification(device:, task:, message: nil)
      unless device.fcm_token.present?
        Rails.logger.info "[FCM] Skipped punishment: no fcm_token for device #{device.device_id}"
        return
      end
      unless credentials_configured?
        Rails.logger.warn "[FCM] Skipped punishment: credentials not configured."
        return
      end

      title = notification_title
      body = message.presence || "Tâche non terminée à temps..."

      data = {
        type: "punishment",
        task_id: task.id.to_s,
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

    def credentials_configured?
      project_id.present? && credentials_json.present?
    end

    private

    def notification_title
      ENV["BG_ENV"] == "staging" ? NOTIFICATION_TITLE_STAGING : NOTIFICATION_TITLE_DEFAULT
    end

    def format_duration_for_notification(total_seconds)
      s = total_seconds.to_i
      return "0 s" if s <= 0

      days, rem = s.divmod(86_400)
      hours, rem = rem.divmod(3600)
      mins, secs = rem.divmod(60)
      parts = []
      parts << "#{days} jour#{'s' if days > 1}" if days.positive?
      parts << "#{hours} h" if hours.positive?
      parts << "#{mins} min" if mins.positive?
      parts << "#{secs} s" if parts.empty? || secs.positive?
      parts.join(" ")
    end

    def showcase_game_label(game_type)
      case game_type.to_s
      when "snake" then "Snake"
      when "quiz" then "Quiz"
      when "dino" then "Dino Run"
      when "tetris" then "Tétris"
      else game_type.to_s.presence || "jeu"
      end
    end

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
      json = ENV["FIREBASE_CREDENTIALS_JSON"]
      return json if json.present?

      path = ENV["FIREBASE_CREDENTIALS_PATH"]
      return nil if path.blank?

      # Resolve relative paths against Rails root (for local dev)
      path = File.expand_path(path, Rails.root) unless Pathname.new(path).absolute?
      File.read(path)
    end
  end
end
