# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "email auth" do
    it "generates a nickname from email when none is provided" do
      user = create(:user, email: "Beta.User+test@dominochain.app", nickname: nil)

      expect(user.nickname).to eq("beta_user_test")
    end

    it "keeps generated nicknames unique" do
      create(:user, email: "beta@dominochain.app", nickname: "beta")
      user = create(:user, email: "beta@other.example", nickname: nil)

      expect(user.nickname).to eq("beta_2")
    end
  end
end
