# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Zap programs", type: :request do
  let(:beta) { create(:user, :beta, nickname: "zapprog") }
  let(:boss) { create(:user, :boss) }

  before do
    stub_beta_catalog_feature_flags
    enable_pishock_catalog!(beta)
    beta.update!(public_pishock_enabled: true)
  end

  describe "boss program" do
    before do
      create(:control, boss: boss, beta: beta, status: :accepted)
      sign_in boss
    end

    it "shows the editor for a controlled beta" do
      get boss_zap_program_path(beta.nickname)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("zap_program.editor.title"))
    end

    it "rejects a boss who does not control the beta" do
      other = create(:user, :boss)
      sign_in other
      get boss_zap_program_path(beta.nickname)
      expect(response).to redirect_to(dashboard_path)
    end

    it "adds a daily slot and arms the program" do
      post boss_zap_program_slots_path(beta.nickname), params: {
        zap_slot: {
          schedule_kind: "daily",
          time_of_day: "08:00",
          pattern_kind: "single",
          intensity: 40,
          duration: 2
        }
      }
      expect(response).to redirect_to(boss_zap_program_path(beta.nickname))
      program = ZapProgram.find_by!(beta: beta, source: "boss")
      expect(program.zap_slots.count).to eq(1)

      post boss_zap_program_arm_path(beta.nickname)
      expect(program.reload.armed?).to be true
    end

    it "disarms when the control is released" do
      program = ZapProgram.find_or_create_for!(beta: beta, source: "boss", boss: boss)
      program.arm!
      control = Control.find_by!(boss: boss, beta: beta)

      post control_release_path(control_id: control.id)
      expect(program.reload.armed?).to be false
    end
  end

  describe "public program" do
    it "renders the editor on the public page" do
      get public_pishock_path(beta.nickname)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("zap_program.editor.title"))
    end

    it "adds a starter moment" do
      post public_zap_program_starter_path(beta.nickname, "morning")
      expect(response).to redirect_to(public_pishock_path(beta.nickname))
      program = ZapProgram.find_by!(beta: beta, source: "public")
      expect(program.zap_slots.count).to eq(1)
      expect(program.armed?).to be false
    end

    it "disarms when the public page is turned off" do
      program = ZapProgram.find_or_create_for!(beta: beta, source: "public")
      program.arm!
      sign_in beta

      patch beta_public_pishock_path, params: { public_pishock_enabled: "0" }
      expect(program.reload.armed?).to be false
    end
  end

  describe "beta stop" do
    it "lets the beta disarm an armed program" do
      program = ZapProgram.find_or_create_for!(beta: beta, source: "public")
      program.arm!
      sign_in beta

      post beta_zap_program_disarm_path(program)
      expect(response).to redirect_to(beta_actions_pishock_path)
      expect(program.reload.armed?).to be false
    end
  end

  describe "pishock off" do
    it "disarms all programs when PiShock is disabled" do
      public_program = ZapProgram.find_or_create_for!(beta: beta, source: "public")
      public_program.arm!
      sign_in beta

      patch beta_pishock_path, params: { pishock_enabled: "0" }
      expect(public_program.reload.armed?).to be false
    end
  end
end
