# frozen_string_literal: true

require "rails_helper"

RSpec.describe RegistrationsController, type: :controller do
  render_views
  include Devise::Test::ControllerHelpers

  let(:user) { create(:user, :beta) }
  let(:confirmation_label) { I18n.t("devise.registrations.delete_confirmation_label") }

  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    sign_in user
  end

  describe "GET #edit" do
    it "renders the hardened deletion UI" do
      get :edit

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("devise.registrations.cancel_account"))
      expect(response.body).to include(I18n.t("devise.registrations.delete_modal_title"))
      expect(response.body).to include(I18n.t("devise.registrations.delete_confirmation_label"))
      expect(response.body).to include('name="account_deletion[confirmation_label]"')
    end
  end

  describe "DELETE #destroy" do
    it "refuses deletion when confirmation label does not match" do
      expect {
        delete :destroy, params: {
          account_deletion: { confirmation_label: "WRONG LABEL" }
        }
      }.not_to change(User, :count)

      expect(response).to redirect_to(edit_user_registration_path)
      expect(flash[:alert]).to eq(I18n.t("devise.registrations.delete_confirmation_mismatch"))
    end

    it "deletes account and associated records when label matches" do
      device = create(:device, user: user)
      add_time_event = ShowcaseAddTimeEvent.create!(user: user, seconds: 30)

      expect {
        delete :destroy, params: {
          account_deletion: { confirmation_label: confirmation_label }
        }
      }.to change(User, :count).by(-1)

      expect(User.where(id: user.id)).to be_empty
      expect(Device.where(id: device.id)).to be_empty
      expect(ShowcaseAddTimeEvent.where(id: add_time_event.id)).to be_empty
    end
  end
end
