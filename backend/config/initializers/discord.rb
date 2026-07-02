# frozen_string_literal: true

Rails.application.config.x.discord_invite_url =
  ENV.fetch("DISCORD_INVITE_URL", "https://discord.gg/YOUR_INVITE_CODE")
