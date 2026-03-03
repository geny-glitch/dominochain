# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    allow(FcmService).to receive(:send_new_task_notification)
    allow(FcmService).to receive(:send_background_changed_notifications)
    allow(FcmService).to receive(:send_proof_reviewed_notification)
    allow(WikimediaCommonsService).to receive(:fetch_and_store_all).and_return(0)
  end
end
