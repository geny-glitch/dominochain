Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "home#index"

  # Admin
  get "admin", to: "admin#index", as: :admin
  get "admin/settings", to: "admin#settings", as: :admin_settings
  patch "admin/settings", to: "admin#update_settings", as: :admin_update_settings
  get "admin/review", to: "admin#review", as: :admin_review
  get "admin/review/images", to: "admin#review_images", as: :admin_review_images
  post "admin/review/images/:id/like", to: "admin#review_like", as: :admin_review_like
  post "admin/review/images/:id/hide", to: "admin#review_hide", as: :admin_review_hide

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # API
  namespace :api do
    post "devices", to: "devices#create"
    patch "devices/:id/fcm_token", to: "devices#update_fcm_token", as: :device_fcm_token
    patch "devices/:id/name", to: "devices#update_name", as: :device_name
    get "devices/:id/wallpaper", to: "devices#wallpaper", as: :device_wallpaper
    post "devices/:id/wallpaper", to: "devices#upload_wallpaper", as: :upload_wallpaper
    get "devices/:id/wallpapers", to: "devices#wallpapers", as: :device_wallpapers
    delete "devices/:id/wallpapers/:wallpaper_id", to: "devices#destroy_wallpaper", as: :destroy_wallpaper
  end

  # Web upload UI
  get "w/:device_id", to: "wallpaper#show", as: :wallpaper_upload
  post "w/:device_id", to: "wallpaper#upload", as: :wallpaper_upload_submit
  post "w/:device_id/wallpapers/:wallpaper_id/set_current", to: "wallpaper#set_current", as: :wallpaper_set_current
  delete "w/:device_id/wallpapers/:wallpaper_id", to: "wallpaper#destroy", as: :wallpaper_destroy
end
