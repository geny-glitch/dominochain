class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("RESEND_FROM_EMAIL", "DominoChain <noreply@mail.dominochain.app>") }
  default reply_to: -> { ENV.fetch("RESEND_REPLYTO_EMAIL", "support@dominochain.app") }
  layout "mailer"
end
