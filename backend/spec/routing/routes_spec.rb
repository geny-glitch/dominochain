# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Route mapping", type: :routing do
  it "maps GET /service-worker to pwa#service_worker" do
    expect(get: "/service-worker").to route_to(controller: "rails/pwa", action: "service_worker")
  end

  it "maps GET /manifest to pwa#manifest" do
    expect(get: "/manifest").to route_to(controller: "rails/pwa", action: "manifest")
  end

  it "maps GET /admin to admin#index" do
    expect(get: "/admin").to route_to(controller: "admin", action: "index")
  end

  it "maps GET /admin/settings to admin#settings" do
    expect(get: "/admin/settings").to route_to(controller: "admin", action: "settings")
  end

  it "maps PATCH /admin/settings to admin#update_settings" do
    expect(patch: "/admin/settings").to route_to(controller: "admin", action: "update_settings")
  end

  it "maps POST /admin/feature_flags_cache/invalidate to admin#invalidate_feature_flags_cache" do
    expect(post: "/admin/feature_flags_cache/invalidate").to route_to(
      controller: "admin",
      action: "invalidate_feature_flags_cache"
    )
  end

  it "maps PATCH /beta/pishock to beta_dashboard#update_pishock" do
    expect(patch: "/beta/pishock").to route_to(controller: "beta_dashboard", action: "update_pishock")
  end

  it "maps POST /beta/pishock/test to beta_dashboard#test_pishock" do
    expect(post: "/beta/pishock/test").to route_to(controller: "beta_dashboard", action: "test_pishock")
  end

  it "maps GET /beta/pishock/debug to pishock_debug#show" do
    expect(get: "/beta/pishock/debug").to route_to(controller: "pishock_debug", action: "show")
  end

  it "maps POST /beta/pishock/debug/clear to pishock_debug#clear" do
    expect(post: "/beta/pishock/debug/clear").to route_to(controller: "pishock_debug", action: "clear")
  end

  it "maps GET /admin/review to admin#review" do
    expect(get: "/admin/review").to route_to(controller: "admin", action: "review")
  end

  it "maps GET /admin/review/images to admin#review_images" do
    expect(get: "/admin/review/images").to route_to(controller: "admin", action: "review_images")
  end

  it "maps POST /admin/review/images/:id/like to admin#review_like" do
    expect(post: "/admin/review/images/1/like").to route_to(controller: "admin", action: "review_like", id: "1")
  end

  it "maps POST /admin/review/images/:id/dislike to admin#review_dislike" do
    expect(post: "/admin/review/images/1/dislike").to route_to(controller: "admin", action: "review_dislike", id: "1")
  end
end
