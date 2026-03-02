Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # API
  namespace :api do
    post "devices", to: "devices#create"
    get "devices/:id/wallpaper", to: "devices#wallpaper", as: :device_wallpaper
    post "devices/:id/wallpaper", to: "devices#upload_wallpaper", as: :upload_wallpaper
  end

  # Web upload UI
  get "w/:device_id", to: "wallpaper#show", as: :wallpaper_upload
  post "w/:device_id", to: "wallpaper#upload", as: :wallpaper_upload_submit
end
