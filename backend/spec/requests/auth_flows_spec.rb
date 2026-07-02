# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth flows", type: :request do
  describe "login flow" do
    it "renders the login view with expected fields" do
      get new_user_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="#{user_session_path}"))
      expect(response.body).to include('name="user[email]"')
      expect(response.body).to include('name="user[password]"')
      expect(response.body).to include("ds-auth-form")
    end

    it "signs in a beta user and redirects to beta dashboard" do
      user = create(:user, :beta, email: "flow-login@dominochain.app", password: "password123")

      post user_session_path, params: {
        user: { email: user.email, password: "password123" }
      }

      expect(response).to redirect_to(beta_dashboard_path)
    end

    it "re-renders the login view when credentials are invalid" do
      create(:user, :beta, email: "flow-invalid@dominochain.app", password: "password123")

      post user_session_path, params: {
        user: { email: "flow-invalid@dominochain.app", password: "wrong-password" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(action="#{user_session_path}"))
      expect(response.body).to include("ds-auth-form")
    end
  end

  describe "password recovery flow" do
    before do
      ActionMailer::Base.deliveries.clear
    end

    it "renders the forgot password view" do
      get new_user_password_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="#{user_password_path}"))
      expect(response.body).to include('name="user[email]"')
      expect(response.body).to include("Forgot your password?")
      expect(response.body).to include("Send me reset password instructions")
      expect(response.body).to include("ds-auth-form")
    end

    it "sends reset instructions and generates HTML/text email views" do
      user = create(:user, :beta, email: "flow-reset@dominochain.app")

      expect {
        post user_password_path, params: { user: { email: user.email } }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(response).to redirect_to(new_user_session_path)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Reset your DominoChain password")
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present
      expect(mail.html_part.body.decoded).to include("Reset my password")
      expect(mail.text_part.body.decoded).to include("Reset your password")
      expect(mail.html_part.body.decoded).to include("/password/edit?reset_password_token=")
      expect(mail.text_part.body.decoded).to include("/password/edit?reset_password_token=")
    end

    it "sends reset instructions using the target user locale" do
      user = create(
        :user,
        :beta,
        email: "flow-reset-fr@dominochain.app",
        beta_ui_prefs: { "locale" => "fr" }
      )

      expect {
        post user_password_path(locale: "en"), params: { user: { email: user.email } }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Réinitialise ton mot de passe DominoChain")
      expect(mail.html_part.body.decoded).to include("Réinitialiser mon mot de passe")
    end

    it "resets the password from reset form and signs user in" do
      user = create(:user, :beta, email: "flow-reset-edit@dominochain.app", password: "password123")
      raw_token = user.send_reset_password_instructions

      get edit_user_password_path(reset_password_token: raw_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="#{user_password_path}"))
      expect(response.body).to include("Change your password")
      expect(response.body).to include('name="user[password]"')
      expect(response.body).to include('name="user[password_confirmation]"')
      expect(response.body).to include("Change my password")

      patch user_password_path, params: {
        user: {
          reset_password_token: raw_token,
          password: "new-password-123",
          password_confirmation: "new-password-123"
        }
      }

      expect(response).to redirect_to(beta_dashboard_path)
      expect(user.reload.valid_password?("new-password-123")).to be(true)
    end
  end

  describe "beta sign up flow" do
    it "renders the beta sign up view with expected fields" do
      get new_user_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="#{user_registration_path}"))
      expect(response.body).to include('name="user[email]"')
      expect(response.body).to include('name="user[password]"')
      expect(response.body).to include('name="user[password_confirmation]"')
      expect(response.body).to include('name="signup_consents[age_confirmed]"')
      expect(response.body).to include('name="signup_consents[terms_accepted]"')
      expect(response.body).not_to include('name="signup_consents[risk_acknowledged]"')
      expect(response.body).to include("ds-auth-form")
    end

    it "creates a beta account and redirects to beta dashboard" do
      expect {
        post user_registration_path, params: {
          user: {
            email: "new-beta-flow@dominochain.app",
            password: "password123",
            password_confirmation: "password123"
          },
          signup_consents: { age_confirmed: "1", terms_accepted: "1" }
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(beta_dashboard_path)

      user = User.find_by!(email: "new-beta-flow@dominochain.app")
      expect(user).to be_beta
      expect(user.nickname).to eq("new_beta_flow")
    end

    it "keeps role as beta even if role param is provided" do
      post user_registration_path, params: {
        user: {
          email: "new-beta-role@dominochain.app",
          password: "password123",
          password_confirmation: "password123",
          role: "boss"
        },
        signup_consents: { age_confirmed: "1", terms_accepted: "1" }
      }

      expect(response).to redirect_to(beta_dashboard_path)
      expect(User.find_by!(email: "new-beta-role@dominochain.app")).to be_beta
    end

    it "re-renders sign up view on invalid payload" do
      expect {
        post user_registration_path, params: {
          user: {
            email: "invalid-beta-flow@dominochain.app",
            password: "password123",
            password_confirmation: "does-not-match"
          }
        }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(action="#{user_registration_path}"))
      expect(response.body).to include("ds-auth-form")
    end

    it "re-renders sign up view when consents are missing" do
      expect {
        post user_registration_path, params: {
          user: {
            email: "no-consent-beta@dominochain.app",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("devise.registrations.consent_age_required"))
    end
  end
end
