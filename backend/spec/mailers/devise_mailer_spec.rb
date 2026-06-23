# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeviseMailer, type: :mailer do
  describe "#reset_password_instructions" do
    it "renders a branded MJML email with a reset link" do
      user = create(:user, email: "reset@dominochain.app")
      mail = described_class.reset_password_instructions(user, "reset-token", {})
      html = mail.html_part.body.decoded

      expect(mail.to).to eq(["reset@dominochain.app"])
      expect(mail.subject).to eq("Reset your DominoChain password")
      expect(html).to include("DominoChain")
      expect(html).to include("Reset my password")
      expect(html).to include("reset-token")
    end
  end

  describe "#confirmation_instructions" do
    it "uses the target user locale instead of current I18n locale" do
      mailer = described_class.new
      captured_locale = nil
      allow(mailer).to receive(:devise_mail) do |_record, _action, _opts, &_block|
        captured_locale = I18n.locale
        Mail::Message.new
      end
      user = create(:user, email: "confirm-fr@dominochain.app", beta_ui_prefs: { "locale" => "fr" })

      I18n.with_locale(:en) do
        mailer.confirmation_instructions(user, "confirm-token", {})
      end

      expect(captured_locale).to eq(:fr)
    end
  end

  describe "#unlock_instructions" do
    it "uses the target user locale instead of current I18n locale" do
      mailer = described_class.new
      captured_locale = nil
      allow(mailer).to receive(:devise_mail) do |_record, _action, _opts, &_block|
        captured_locale = I18n.locale
        Mail::Message.new
      end
      user = create(:user, email: "unlock-fr@dominochain.app", beta_ui_prefs: { "locale" => "fr" })

      I18n.with_locale(:en) do
        mailer.unlock_instructions(user, "unlock-token", {})
      end

      expect(captured_locale).to eq(:fr)
    end
  end
end
