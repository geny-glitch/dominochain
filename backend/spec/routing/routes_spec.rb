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
