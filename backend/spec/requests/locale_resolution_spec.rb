# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale resolution", type: :request do
  it "uses Accept-Language for guests and falls back to English" do
    get root_path, headers: { "Accept-Language" => "fr-FR,fr;q=0.9,en;q=0.8" }

    expect(response).to have_http_status(:ok)
    expect(session[:locale]).to eq("fr")
    expect(I18n.locale).to eq(:fr)
  end

  it "falls back to English when Accept-Language has no supported locale" do
    get root_path, headers: { "Accept-Language" => "de-DE,de;q=0.9" }

    expect(response).to have_http_status(:ok)
    expect(I18n.locale).to eq(:en)
  end

  it "prefers an explicit locale param over Accept-Language" do
    get root_path, params: { locale: "es" }, headers: { "Accept-Language" => "fr" }

    expect(session[:locale]).to eq("es")
    expect(I18n.locale).to eq(:es)
  end
end
