# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session CSRF", type: :request do
  let(:user) { create(:user, :beta, email: "csrf-test@dominochain.app", password: "password123") }

  around do |example|
    original_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery
  end

  before do
    host! "beta.dominochain.app"
    https!
  end

  def authenticity_token_from(response)
    response.body[/name="authenticity_token" value="([^"]+)"/, 1]
  end

  def log_in_via_form
    get new_user_session_path
    post user_session_path, params: {
      authenticity_token: authenticity_token_from(response),
      user: { email: user.email, password: "password123" }
    }
    follow_redirect!
  end

  it "accepts login POST after GET" do
    log_in_via_form
    expect(response).to have_http_status(:ok)
  end

  it "accepts DELETE logout and login again" do
    log_in_via_form

    get beta_dashboard_path
    token = authenticity_token_from(response)
    expect(token).to be_present

    delete destroy_user_session_path, params: { authenticity_token: token }
    expect(response).to have_http_status(:redirect)

    get new_user_session_path
    post user_session_path, params: {
      authenticity_token: authenticity_token_from(response),
      user: { email: user.email, password: "password123" }
    }

    expect(response.body).not_to include("The change you wanted was rejected")
    expect(response).to have_http_status(:redirect)
  end
end
