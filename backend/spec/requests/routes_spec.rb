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

    it "GET /up returns 200" do
      get rails_health_check_path
      expect(response).to have_http_status(:ok)
    end

    # PWA routes require app/views/pwa/* templates - tested in spec/routing/routes_spec.rb
  end

  describe "Devise POST routes" do
    let(:user) { create(:user, :beta, nickname: "testbeta", password: "password123") }

    it "POST /login signs in and redirects" do
      post user_session_path, params: { user: { nickname: user.nickname, password: "password123" } }
      expect(response).to have_http_status(:redirect)
    end

    it "POST /signup creates user and redirects" do
      post user_registration_path, params: {
        user: { nickname: "newuser", password: "password123", password_confirmation: "password123" }
      }
      expect(response).to have_http_status(:redirect)
    end

    it "POST /signup/boss creates boss and redirects" do
      post boss_registration_path, params: {
        user: { nickname: "newboss", password: "password123", password_confirmation: "password123" }
      }
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

    it "returns 200 when beta is authenticated" do
      beta = create(:user, :beta)
      sign_in beta
      get beta_dashboard_path
      expect(response).to have_http_status(:ok)
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
  end

  describe "API routes" do
    describe "Auth (no device token required)" do
      it "POST /api/auth/login returns 401 with invalid credentials" do
        post api_auth_login_path, params: { nickname: "unknown", password: "wrong" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "POST /api/auth/login returns 200 with valid credentials" do
        user = create(:user, :beta, nickname: "apiuser", password: "password123")
        post api_auth_login_path, params: {
          nickname: user.nickname, password: "password123", device_id: "test-device"
        }
        expect(response).to have_http_status(:ok)
      end

      it "POST /api/auth/register returns 201" do
        post api_auth_register_path, params: {
          nickname: "newapi", password: "password123", password_confirmation: "password123",
          device_id: "device-123"
        }
        expect(response).to have_http_status(:created)
      end

      it "POST /api/auth/logout returns 204" do
        post api_auth_logout_path
        expect(response).to have_http_status(:no_content)
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
          nickname: beta.nickname, password: "password123", device_id: "fresh-device"
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
