# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Routes", type: :request do
  describe "Public routes" do
    it "GET / returns 200" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /login returns 200" do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /signup returns 200" do
      get new_user_registration_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /signup/boss returns 200" do
      get new_boss_registration_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /terms returns 200" do
      get terms_path
      expect(response).to have_http_status(:ok)
    end

    it "GET /up returns 200" do
      get rails_health_check_path
      expect(response).to have_http_status(:ok)
    end

    # PWA routes require app/views/pwa/* templates - tested in spec/routing/routes_spec.rb
  end

  describe "Devise POST routes" do
    let(:user) { create(:user, :beta, nickname: "testbeta", email: "testbeta@dominochain.app", password: "password123") }

    it "POST /login signs in and redirects" do
      post user_session_path, params: { user: { email: user.email, password: "password123" } }
      expect(response).to have_http_status(:redirect)
    end

    it "POST /signup creates user and redirects" do
      post user_registration_path, params: {
        user: { email: "newuser@dominochain.app", password: "password123", password_confirmation: "password123" },
        signup_consents: { age_confirmed: "1", terms_accepted: "1" }
      }
      expect(response).to have_http_status(:redirect)
      expect(User.find_by!(email: "newuser@dominochain.app").nickname).to eq("newuser")
    end

    it "POST /signup/boss creates boss and redirects" do
      post boss_registration_path, params: {
        user: { email: "newboss@dominochain.app", password: "password123", password_confirmation: "password123" },
        signup_consents: { age_confirmed: "1", terms_accepted: "1" }
      }
      expect(response).to have_http_status(:redirect)
      expect(User.find_by!(email: "newboss@dominochain.app").nickname).to eq("newboss")
    end

    it "POST /password sends reset instructions" do
      user = create(:user, email: "recover@dominochain.app")

      expect {
        post user_password_path, params: { user: { email: user.email } }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(user.reload.reset_password_token).to be_present
      expect(ActionMailer::Base.deliveries.last.subject).to eq("Reset your DominoChain password")
    end

    it "GET /logout signs out and redirects" do
      sign_in user
      get destroy_user_session_path
      expect(response).to have_http_status(:redirect)
    end

    it "DELETE /logout signs out and redirects" do
      sign_in user
      delete destroy_user_session_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "Dashboard (boss only)" do
    it "redirects to login when not authenticated" do
      get dashboard_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns 200 when boss is authenticated" do
      boss = create(:user, :boss)
      sign_in boss
      get dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects beta to beta_dashboard" do
      beta = create(:user, :beta)
      sign_in beta
      get dashboard_path
      expect(response).to redirect_to(beta_dashboard_path)
    end
  end

  describe "Beta dashboard" do
    it "redirects to login when not authenticated" do
      get beta_dashboard_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns 200 on /beta when beta is authenticated" do
      beta = create(:user, :beta)
      sign_in beta
      get beta_dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 on Sources PuryFi when beta is authenticated" do
      beta = create(:user, :beta)
      sign_in beta
      get beta_sources_puryfi_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /beta/pishock/test" do
    it "redirects to login when not authenticated" do
      post beta_pishock_test_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects with alert when PiShock fields are empty" do
      beta = create(:user, :beta)
      sign_in beta
      post beta_pishock_test_path
      expect(response).to redirect_to(beta_actions_pishock_path)
      expect(flash[:alert]).to include("Enregistre")
    end

    it "calls PishockService and sets flash on success" do
      beta = create(:user, :beta, pishock_username: "u", pishock_share_code: "c", pishock_api_key: "k")
      sign_in beta
      allow(PishockService).to receive(:test_connection!).and_return(:ok)
      post beta_pishock_test_path
      expect(response).to redirect_to(beta_actions_pishock_path)
      expect(flash[:notice]).to be_present
      expect(PishockService).to have_received(:test_connection!).with(user: satisfy { |u| u.id == beta.id })
    end
  end

  describe "Strava beta routes" do
    it "redirects to login when not authenticated" do
      post beta_strava_goals_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "creates a Strava goal for the authenticated beta" do
      beta = create(:user, :beta, strava_access_token: "access", strava_refresh_token: "refresh")
      sign_in beta

      post beta_strava_goals_path, params: {
        name: "Cardio",
        enabled: "1",
        required_count: "2",
        window_preset: "custom",
        window_days: "10",
        check_time: "06:30",
        time_zone: "Paris",
        min_duration_minutes: "30",
        activity_types: "Run, Ride",
        device_names: "Garmin"
      }

      expect(response).to redirect_to(beta_sources_strava_path)
      goal = beta.strava_goals.last
      expect(goal.name).to eq("Cardio")
      expect(goal.required_count).to eq(2)
      expect(goal.window_days).to eq(10)
      expect(goal.check_time_label).to eq("06:30")
      expect(goal.time_zone).to eq("Paris")
      expect(goal.min_duration_seconds).to eq(1_800)
      expect(goal.activity_types).to eq(%w[Run Ride])
      expect(goal.device_names).to eq([ "Garmin" ])
      expect(goal.chaster_penalty_seconds).to eq(0)
      expect(goal.scenario_set).to be_empty
    end

    it "merges strava_sport_type into activity_types" do
      beta = create(:user, :beta, strava_access_token: "access", strava_refresh_token: "refresh")
      sign_in beta

      post beta_strava_goals_path, params: {
        name: "Trail",
        enabled: "1",
        required_count: "1",
        window_preset: "weekly",
        check_time: "08:00",
        time_zone: "Paris",
        strava_sport_type: "TrailRun",
        activity_types: "Ride",
        min_duration_minutes: "20"
      }

      expect(response).to redirect_to(beta_sources_strava_path)
      goal = beta.strava_goals.last
      expect(goal.activity_types).to eq(%w[TrailRun Ride])
    end

    it "disconnects Strava and disables goals" do
      beta = create(:user, :beta, strava_access_token: "access", strava_refresh_token: "refresh")
      create(:strava_goal, user: beta, enabled: true)
      sign_in beta

      delete strava_disconnect_path

      expect(response).to redirect_to(beta_sources_strava_path)
      expect(beta.reload.strava_access_token).to be_nil
      expect(beta.strava_goals.first.enabled).to be false
    end
  end

  describe "Beta task routes" do
    let(:beta) { create(:user, :beta) }
    let(:device) { create(:device, user: beta) }
    let(:task) { create(:task, user: beta) }

    before { sign_in beta }

    it "GET /beta/tasks/:id returns 200" do
      get beta_task_path(task.id)
      expect(response).to have_http_status(:ok)
    end

    it "POST /beta/tasks/:id/proof returns redirect" do
      post beta_task_proof_path(task.id), params: { text: "Done!" }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "Control routes" do
    let(:beta) { create(:user, :beta, nickname: "controlbeta") }
    let(:boss) { create(:user, :boss) }
    let(:control) { create(:control, boss: boss, beta: beta) }
    let(:control_request) { create(:control_request, beta: beta, boss: boss) }

    describe "accept_from_link (GET)" do
      it "redirects to login when not authenticated" do
        get control_accept_from_link_path(beta.nickname)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "returns 200 when authenticated" do
        sign_in boss
        get control_accept_from_link_path(beta.nickname)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "accept_from_link_submit (POST)" do
      it "redirects to login when not authenticated" do
        post control_accept_from_link_submit_path(beta.nickname)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "redirects when authenticated" do
        sign_in boss
        post control_accept_from_link_submit_path(beta.nickname)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "release, accept_request, reject_request" do
      it "redirects to login when not authenticated" do
        post control_release_path(control_id: control.id)
        expect(response).to redirect_to(new_user_session_path)

        post control_accept_request_path(request_id: control_request.id)
        expect(response).to redirect_to(new_user_session_path)

        post control_reject_request_path(request_id: control_request.id)
        expect(response).to redirect_to(new_user_session_path)
      end

      it "returns redirect when boss is authenticated" do
        sign_in boss
        post control_release_path(control_id: control.id)
        expect(response).to have_http_status(:redirect)

        sign_in boss
        post control_accept_request_path(request_id: control_request.id)
        expect(response).to have_http_status(:redirect)

        beta2 = create(:user, :beta, nickname: "rejectbeta")
        cr = create(:control_request, beta: beta2, boss: boss, status: :pending)
        sign_in boss
        post control_reject_request_path(request_id: cr.id)
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "Admin routes" do
    it "redirects to login when not authenticated" do
      get admin_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects non-admin to root" do
      boss = create(:user, :boss)
      sign_in boss
      get admin_path
      expect(response).to redirect_to(root_path)
    end

    it "GET /admin/jobs redirects to login when not authenticated" do
      get "/admin/jobs"
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when admin is authenticated" do
      let(:admin) { create(:user, :admin) }
      let(:modern_headers) do
        { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0" }
      end

      before { sign_in admin }

      it "GET /admin returns 200" do
        get admin_path, headers: modern_headers
        expect(response).to have_http_status(:ok)
      end

      it "GET /admin/settings returns 200" do
        AppSetting.instance
        get admin_settings_path, headers: modern_headers
        expect(response).to have_http_status(:ok)
      end

      it "GET /admin/review returns 200" do
        get admin_review_path, headers: modern_headers
        expect(response).to have_http_status(:ok)
      end

      it "GET /admin/wallpaper_pairs returns 200" do
        get admin_wallpaper_pairs_path, headers: modern_headers
        expect(response).to have_http_status(:ok)
      end

      it "GET /admin/jobs returns 200" do
        get "/admin/jobs", headers: modern_headers
        expect(response).to have_http_status(:ok)
      end

      it "POST /admin/feature_flags_cache/invalidate returns redirect" do
        post admin_invalidate_feature_flags_cache_path, headers: modern_headers
        expect(response).to have_http_status(:redirect)
      end

      # PATCH /admin/settings route tested in spec/routing/routes_spec.rb

      it "POST /admin/controls/:id/release returns redirect" do
        beta = create(:user, :beta)
        control = create(:control, boss: admin, beta: beta)
        post admin_release_control_path(control_id: control.id), headers: modern_headers
        expect(response).to have_http_status(:redirect)
      end

      # Like/dislike tested in spec/routing/routes_spec.rb (route mapping)
    end
  end

  describe "Wallpaper routes (w/:nickname)" do
    let(:beta) { create(:user, :beta, nickname: "wallbeta") }
    let(:boss) { create(:user, :boss) }
    let!(:device) { create(:device, user: beta) }
    let!(:control) { create(:control, boss: boss, beta: beta) }

    it "redirects to login when not authenticated" do
      get wallpaper_upload_path(beta.nickname)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects to control accept when boss has no control" do
      boss2 = create(:user, :boss, nickname: "boss2")
      sign_in boss2
      get wallpaper_upload_path(beta.nickname)
      expect(response).to redirect_to(control_accept_from_link_path(beta.nickname))
    end

    it "returns 200 when boss with control is authenticated" do
      sign_in boss
      get wallpaper_upload_path(beta.nickname)
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 when admin is authenticated" do
      admin = create(:user, :admin)
      sign_in admin
      get wallpaper_upload_path(beta.nickname)
      expect(response).to have_http_status(:ok)
    end

    context "when boss with control is authenticated" do
      before { sign_in boss }

      it "GET w/:nickname/control/accept redirects when boss already has control" do
        get control_accept_from_link_path(beta.nickname)
        expect(response).to have_http_status(:redirect)
      end

      it "GET w/:nickname/tasks/:id returns 200" do
        task = create(:task, user: beta)
        get wallpaper_task_path(beta.nickname, task.id)
        expect(response).to have_http_status(:ok)
      end

      it "DELETE w/:nickname/devices/:device_id returns redirect" do
        delete wallpaper_destroy_device_path(beta.nickname, device.device_id)
        expect(response).to have_http_status(:redirect)
        expect(Device.exists?(device.id)).to be false
      end

      it "DELETE w/:nickname/screenshots/:id returns redirect" do
        screenshot = create(:device_screenshot, device: device)
        delete wallpaper_destroy_screenshot_path(beta.nickname, screenshot.id)
        expect(response).to have_http_status(:redirect)
        expect(DeviceScreenshot.exists?(screenshot.id)).to be false
      end

      it "DELETE w/:nickname/applications/:id returns redirect" do
        wallpaper = create(:wallpaper, device: device)
        application = device.wallpaper_applications.create!(wallpaper: wallpaper, applied_at: Time.current)
        delete wallpaper_destroy_application_path(beta.nickname, application.id)
        expect(response).to have_http_status(:redirect)
        expect(WallpaperApplication.exists?(application.id)).to be false
      end
    end
  end

  describe "Tasks routes" do
    let(:beta) { create(:user, :beta, nickname: "taskbeta") }
    let(:boss) { create(:user, :boss) }
    let!(:device) { create(:device, user: beta) }
    let!(:control) { create(:control, boss: boss, beta: beta) }
    let(:task) { create(:task, user: beta) }

    before { sign_in boss }

    it "POST w/:nickname/tasks returns redirect" do
      post wallpaper_tasks_path(beta.nickname), params: {
        task: { name: "Test", deadline_at: 1.day.from_now, expected_proof: "Proof" }
      }
      expect(response).to have_http_status(:redirect)
    end

    it "DELETE w/:nickname/tasks/:id returns redirect" do
      delete wallpaper_task_destroy_path(beta.nickname, task.id)
      expect(response).to have_http_status(:redirect)
    end

    it "POST w/:nickname/tasks/:id/review_proof returns redirect" do
      create(:proof_of_completion, task: task, status: "pending")
      post wallpaper_task_review_proof_path(beta.nickname, task.id), params: { accept: "Accepter" }
      expect(response).to have_http_status(:redirect)
    end

    it "POST w/:nickname/tasks/:id/punish returns redirect and creates punishment" do
      expired_task = create(:task, user: beta, deadline_at: 1.hour.ago, status: "pending")
      post wallpaper_task_punish_path(beta.nickname, expired_task.id, device_id: device.device_id), params: { punishment_message: "Tu aurais dû finir !" }
      expect(response).to have_http_status(:redirect)
      expect(expired_task.reload.punishments.count).to eq(1)
      expect(expired_task.punishments.first.message).to eq("Tu aurais dû finir !")
    end
  end

  describe "API routes" do
    describe "Auth (no device token required)" do
      it "POST /api/auth/login returns 401 with invalid credentials" do
        post api_auth_login_path, params: { email: "unknown@dominochain.app", password: "wrong" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "POST /api/auth/login returns 200 with valid credentials" do
        user = create(:user, :beta, nickname: "apiuser", email: "apiuser@dominochain.app", password: "password123")
        post api_auth_login_path, params: {
          email: user.email, password: "password123", device_id: "test-device"
        }
        expect(response).to have_http_status(:ok)
      end

      it "POST /api/auth/login accepts nickname for legacy clients" do
        user = create(:user, :beta, nickname: "legacyuser", email: "legacyuser@dominochain.app", password: "password123")
        post api_auth_login_path, params: {
          nickname: user.nickname, password: "password123", device_id: "test-device"
        }
        expect(response).to have_http_status(:ok)
      end

      it "POST /api/auth/register returns 201 with nickname only for legacy clients" do
        post api_auth_register_path, params: {
          nickname: "legacybeta", password: "password123", password_confirmation: "password123",
          device_id: "device-legacy"
        }
        expect(response).to have_http_status(:created)
        user = User.find_by!(email: "legacybeta@dominochain.app")
        expect(user.nickname).to eq("legacybeta")
      end

      it "POST /api/auth/register returns 201" do
        post api_auth_register_path, params: {
          email: "newapi@dominochain.app", password: "password123", password_confirmation: "password123",
          device_id: "device-123"
        }
        expect(response).to have_http_status(:created)
        user = User.find_by!(email: "newapi@dominochain.app")
        expect(user.nickname).to eq("newapi")
        expect(user.showcase_quiz_enabled).to be false
        expect(user.showcase_snake_enabled).to be false
        expect(user.showcase_dino_enabled).to be false
        expect(user.showcase_tetris_enabled).to be false
        expect(user.showcase_backdoor_enabled).to be false
        expect(user.beta_ui_prefs.dig("catalog_visibility", "sources")).to eq({
          "puryfi" => false,
          "cigarettes" => false,
          "strava" => false,
          "showcase" => false
        })
        expect(user.beta_ui_prefs.dig("catalog_visibility", "actions")).to eq({
          "chaster" => false,
          "pishock" => false
        })
      end

      it "POST /api/auth/logout returns 204" do
        post api_auth_logout_path
        expect(response).to have_http_status(:no_content)
      end
    end

    describe "DELETE /chaster/disconnect" do
      it "keeps Chaster connected when a lock is active" do
        beta = create(
          :user,
          :beta,
          chaster_access_token: "access",
          chaster_refresh_token: "refresh",
          chaster_token_expires_at: 1.hour.from_now
        )
        chaster_service = instance_double(ChasterService, current_lock: { id: "lock-active" })
        allow(ChasterService).to receive(:new).with(beta).and_return(chaster_service)
        sign_in beta

        delete chaster_disconnect_path

        expect(response).to redirect_to(beta_actions_chaster_path)
        expect(flash[:alert]).to eq("Impossible de déconnecter Chaster tant qu'un lock est actif.")
        expect(beta.reload.chaster_access_token).to eq("access")
        expect(beta.chaster_refresh_token).to eq("refresh")
      end

      it "disconnects Chaster when no lock is active" do
        beta = create(
          :user,
          :beta,
          chaster_access_token: "access",
          chaster_refresh_token: "refresh",
          chaster_token_expires_at: 1.hour.from_now
        )
        chaster_service = instance_double(ChasterService, current_lock: nil)
        allow(ChasterService).to receive(:new).with(beta).and_return(chaster_service)
        sign_in beta

        delete chaster_disconnect_path

        expect(response).to redirect_to(beta_actions_chaster_path)
        expect(flash[:notice]).to eq("Chaster déconnecté.")
        expect(beta.reload.chaster_access_token).to be_nil
        expect(beta.chaster_refresh_token).to be_nil
      end
    end

    describe "Control requests (device auth required)" do
      it "POST /api/control_requests returns 401 without auth" do
        post api_control_requests_path, params: { boss_nickname: "boss" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "POST /api/control_requests returns 201 with valid auth" do
        beta = create(:user, :beta)
        boss = create(:user, :boss, nickname: "apiboss")
        device = create(:device, user: beta)
        post api_control_requests_path,
          params: { boss_nickname: boss.nickname },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:created)
      end
    end

    describe "GET /api/auth/me" do
      it "returns 401 without auth" do
        get "/api/auth/me"
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns nickname and boss_nickname when beta is controlled" do
        beta = create(:user, :beta, nickname: "mebeta")
        boss = create(:user, :boss, nickname: "myboss")
        create(:control, boss: boss, beta: beta, status: :accepted)
        device = create(:device, user: beta)
        get "/api/auth/me",
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["nickname"]).to eq("mebeta")
        expect(json["boss_nickname"]).to eq("myboss")
        expect(json["role"]).to eq("beta")
      end

      it "returns boss_nickname null when beta has no control" do
        beta = create(:user, :beta, nickname: "freebeta")
        device = create(:device, user: beta)
        get "/api/auth/me",
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["nickname"]).to eq("freebeta")
        expect(json["boss_nickname"]).to be_nil
        expect(json["role"]).to eq("beta")
      end
    end

    describe "GET /api/showcase_settings" do
      it "returns 401 without auth" do
        get "/api/showcase_settings"
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 403 for a boss (not beta)" do
        boss = create(:user, :boss, nickname: "apibossshow")
        device = create(:device, user: boss)
        get "/api/showcase_settings",
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:forbidden)
      end

      it "returns game flags for beta" do
        beta = create(:user, :beta, showcase_quiz_enabled: true, showcase_snake_enabled: true, showcase_dino_enabled: true, showcase_tetris_enabled: true)
        device = create(:device, user: beta)
        get "/api/showcase_settings",
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["showcase_quiz_enabled"]).to be true
        expect(json["showcase_snake_enabled"]).to be true
        expect(json["showcase_dino_enabled"]).to be true
        expect(json["showcase_tetris_enabled"]).to be true
        expect(json["showcase_backdoor_enabled"]).to be true
        expect(json["showcase_quiz_seconds_per_point"]).to eq(1)
        expect(json["showcase_snake_seconds_per_fruit"]).to eq(300)
        expect(json["showcase_dino_seconds_per_obstacle"]).to eq(300)
        expect(json["showcase_tetris_seconds_per_line"]).to eq(60)
      end
    end

    describe "PATCH /api/showcase_settings" do
      it "rejects when all showcase entries would be disabled" do
        beta = create(
          :user, :beta,
          showcase_quiz_enabled: true,
          showcase_snake_enabled: true,
          showcase_dino_enabled: true,
          showcase_tetris_enabled: true,
          showcase_backdoor_enabled: true
        )
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: {
            showcase_quiz_enabled: false,
            showcase_snake_enabled: false,
            showcase_dino_enabled: false,
            showcase_tetris_enabled: false,
            showcase_backdoor_enabled: false
          },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(beta.reload.showcase_quiz_enabled).to be true
        expect(beta.showcase_snake_enabled).to be true
        expect(beta.showcase_dino_enabled).to be true
        expect(beta.showcase_tetris_enabled).to be true
        expect(beta.showcase_backdoor_enabled).to be true
      end

      it "allows disabling one game when the other stays on" do
        beta = create(:user, :beta, showcase_quiz_enabled: true, showcase_snake_enabled: true)
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_snake_enabled: false },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        expect(beta.reload.showcase_quiz_enabled).to be true
        expect(beta.showcase_snake_enabled).to be false
      end

      it "allows disabling visible games when backdoor stays enabled" do
        beta = create(
          :user, :beta,
          showcase_quiz_enabled: true,
          showcase_snake_enabled: true,
          showcase_dino_enabled: true,
          showcase_tetris_enabled: true,
          showcase_backdoor_enabled: true
        )
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_quiz_enabled: false, showcase_snake_enabled: false, showcase_dino_enabled: false, showcase_tetris_enabled: false },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        expect(beta.reload.showcase_quiz_enabled).to be false
        expect(beta.showcase_snake_enabled).to be false
        expect(beta.showcase_dino_enabled).to be false
        expect(beta.showcase_tetris_enabled).to be false
        expect(beta.showcase_backdoor_enabled).to be true
      end

      it "updates showcase_snake_seconds_per_fruit" do
        beta = create(:user, :beta, showcase_snake_seconds_per_fruit: 300)
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_snake_seconds_per_fruit: 600 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        expect(beta.reload.showcase_snake_seconds_per_fruit).to eq(600)
        json = JSON.parse(response.body)
        expect(json["showcase_snake_seconds_per_fruit"]).to eq(600)
      end

      it "updates per-game showcase seconds independently" do
        beta = create(
          :user, :beta,
          showcase_quiz_seconds_per_point: 1,
          showcase_snake_seconds_per_fruit: 300,
          showcase_dino_seconds_per_obstacle: 300,
          showcase_tetris_seconds_per_line: 60
        )
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_quiz_seconds_per_point: 2, showcase_dino_seconds_per_obstacle: 120, showcase_tetris_seconds_per_line: 90 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        expect(beta.reload.showcase_quiz_seconds_per_point).to eq(2)
        expect(beta.showcase_snake_seconds_per_fruit).to eq(300)
        expect(beta.showcase_dino_seconds_per_obstacle).to eq(120)
        expect(beta.showcase_tetris_seconds_per_line).to eq(90)
        json = JSON.parse(response.body)
        expect(json["showcase_quiz_seconds_per_point"]).to eq(2)
        expect(json["showcase_snake_seconds_per_fruit"]).to eq(300)
        expect(json["showcase_dino_seconds_per_obstacle"]).to eq(120)
        expect(json["showcase_tetris_seconds_per_line"]).to eq(90)
      end

      it "rejects decreasing snake seconds within 24 hours of last change" do
        beta = create(
          :user, :beta,
          showcase_snake_seconds_per_fruit: 600,
          showcase_snake_seconds_per_fruit_at: 23.hours.ago
        )
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_snake_seconds_per_fruit: 300 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(beta.reload.showcase_snake_seconds_per_fruit).to eq(600)
      end

      it "allows decreasing snake seconds after 24 hours" do
        beta = create(
          :user, :beta,
          showcase_snake_seconds_per_fruit: 600
        )
        beta.update_column(:showcase_snake_seconds_per_fruit_at, 25.hours.ago)
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_snake_seconds_per_fruit: 300 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        expect(beta.reload.showcase_snake_seconds_per_fruit).to eq(300)
      end

      it "rejects decreasing dino seconds within 24 hours of last change" do
        beta = create(
          :user, :beta,
          showcase_dino_seconds_per_obstacle: 600,
          showcase_dino_seconds_per_obstacle_at: 23.hours.ago
        )
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_dino_seconds_per_obstacle: 300 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(beta.reload.showcase_dino_seconds_per_obstacle).to eq(600)
      end

      it "rejects decreasing tetris seconds within 24 hours of last change" do
        beta = create(
          :user, :beta,
          showcase_tetris_seconds_per_line: 120,
          showcase_tetris_seconds_per_line_at: 23.hours.ago
        )
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_tetris_seconds_per_line: 60 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(beta.reload.showcase_tetris_seconds_per_line).to eq(120)
      end

      it "allows decreasing tetris seconds after 24 hours" do
        beta = create(
          :user, :beta,
          showcase_tetris_seconds_per_line: 120
        )
        beta.update_column(:showcase_tetris_seconds_per_line_at, 25.hours.ago)
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_tetris_seconds_per_line: 60 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:ok)
        expect(beta.reload.showcase_tetris_seconds_per_line).to eq(60)
      end

      it "rejects decreasing quiz seconds within 24 hours of last change" do
        beta = create(
          :user, :beta,
          showcase_quiz_seconds_per_point: 3,
          showcase_quiz_seconds_per_point_at: 23.hours.ago
        )
        device = create(:device, user: beta)
        patch "/api/showcase_settings",
          params: { showcase_quiz_seconds_per_point: 1 },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(beta.reload.showcase_quiz_seconds_per_point).to eq(3)
      end
    end

    describe "PATCH /api/auth/password" do
      it "returns 401 without auth" do
        patch "/api/auth/password", params: { current_password: "x", password: "newpass123", password_confirmation: "newpass123" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 204 with valid auth and correct current password" do
        beta = create(:user, :beta, nickname: "pwbeta", password: "password123")
        device = create(:device, user: beta)
        patch "/api/auth/password",
          params: { current_password: "password123", password: "newpass123", password_confirmation: "newpass123" },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:no_content)
        expect(beta.reload.valid_password?("newpass123")).to be true
      end

      it "returns 401 with wrong current password" do
        beta = create(:user, :beta, nickname: "pwbeta2", password: "password123")
        device = create(:device, user: beta)
        patch "/api/auth/password",
          params: { current_password: "wrong", password: "newpass123", password_confirmation: "newpass123" },
          headers: { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "Devices (device auth required)" do
      let(:beta) { create(:user, :beta) }
      let(:device) { create(:device, user: beta) }
      let(:auth_headers) do
        { "X-Device-Id" => device.device_id, "X-Device-Token" => device.auth_token }
      end

      it "POST /api/devices returns 401 without auth" do
        post api_devices_path, params: { device_id: "new-device" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "POST /api/devices creates device when user has auth (via login)" do
        post api_auth_login_path, params: {
          email: beta.email, password: "password123", device_id: "fresh-device"
        }
        expect(response).to have_http_status(:ok)
        token = JSON.parse(response.body)["token"]
        device_id = JSON.parse(response.body)["device_id"]
        post api_devices_path,
          params: { device_id: "second-device" },
          headers: { "X-Device-Id" => device_id, "X-Device-Token" => token }
        expect(response).to have_http_status(:ok)
      end

      it "GET /api/devices/:id/wallpaper returns 401 without auth" do
        get "/api/devices/#{device.device_id}/wallpaper"
        expect(response).to have_http_status(:unauthorized)
      end

      it "GET /api/devices/:id/wallpaper returns 200 or 404 with auth" do
        get "/api/devices/#{device.device_id}/wallpaper", headers: auth_headers
        expect(response).to have_http_status(:ok).or have_http_status(:not_found)
      end

      it "GET /api/devices/:id/wallpapers returns 200 with auth" do
        get "/api/devices/#{device.device_id}/wallpapers", headers: auth_headers
        expect(response).to have_http_status(:ok)
      end

      it "GET /api/devices/:id/tasks returns 200 with auth" do
        get "/api/devices/#{device.device_id}/tasks", headers: auth_headers
        expect(response).to have_http_status(:ok)
      end

      it "PATCH /api/devices/:id/fcm_token returns 204 with auth" do
        patch "/api/devices/#{device.device_id}/fcm_token", params: { fcm_token: "new-token" }, headers: auth_headers
        expect(response).to have_http_status(:no_content)
      end

      it "PATCH /api/devices/:id/name returns 204 with auth" do
        patch "/api/devices/#{device.device_id}/name", params: { name: "My Phone" }, headers: auth_headers
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
