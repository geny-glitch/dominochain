Rails.application.routes.draw do
  devise_for :users, path: "", path_names: {
    sign_in: "login", sign_out: "logout", sign_up: "signup"
  }, controllers: { registrations: "registrations" }

  devise_scope :user do
    get "signup/boss", to: "boss_registrations#new", as: :new_boss_registration
    post "signup/boss", to: "boss_registrations#create", as: :boss_registration
  end

  get "dashboard", to: "dashboard#show", as: :dashboard
  get "beta", to: "beta_dashboard#show", as: :beta_dashboard

  # Vitrine du beta (page publique)
  get "showcase/:nickname", to: "showcase#show", as: :showcase
  get "showcase/:nickname/quiz", to: "showcase#quiz", as: :showcase_quiz
  get "showcase/:nickname/snake", to: "showcase#snake", as: :showcase_snake
  post "showcase/:nickname/add_time", to: "showcase#add_time", as: :showcase_add_time
  post "showcase/:nickname/sessions", to: "showcase#create_session", as: :showcase_create_session
  patch "showcase/:nickname/sessions/:id", to: "showcase#update_session", as: :showcase_update_session
  get "showcase/:nickname/leaderboard", to: "showcase#leaderboard", as: :showcase_leaderboard
  get "showcase/:nickname/questions", to: "showcase#questions", as: :showcase_questions
  post "showcase/:nickname/check_answer", to: "showcase#check_answer", as: :showcase_check_answer

  # Chaster OAuth (beta only)
  get "chaster/connect", to: "chaster#connect", as: :chaster_connect
  get "chaster/callback", to: "chaster#callback", as: :chaster_callback
  delete "chaster/disconnect", to: "chaster#disconnect", as: :chaster_disconnect
  get "beta/tasks/:id", to: "beta_dashboard#task", as: :beta_task
  post "beta/tasks/:id/proof", to: "beta_dashboard#submit_proof", as: :beta_task_proof
  post "control/release", to: "controls#release", as: :control_release
  post "control/accept_request", to: "controls#accept_request", as: :control_accept_request
  post "control/reject_request", to: "controls#reject_request", as: :control_reject_request

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "home#index"

  # Admin
  get "admin", to: "admin#index", as: :admin
  get "admin/settings", to: "admin#settings", as: :admin_settings
  patch "admin/settings", to: "admin#update_settings", as: :admin_update_settings
  post "admin/controls/:control_id/release", to: "admin#release_control", as: :admin_release_control
  get "admin/review", to: "admin#review", as: :admin_review
  get "admin/review/images", to: "admin#review_images", as: :admin_review_images
  post "admin/review/images/:id/like", to: "admin#review_like", as: :admin_review_like
  post "admin/review/images/:id/dislike", to: "admin#review_dislike", as: :admin_review_dislike

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # APIR
  namespace :api do
    post "auth/login", to: "auth#login"
    post "auth/register", to: "auth#register"
    post "auth/logout", to: "auth#logout"
    get "auth/me", to: "me#show"
    patch "auth/password", to: "passwords#update"

    post "control_requests", to: "control_requests#create"

    post "devices", to: "devices#create"
    patch "devices/:id/fcm_token", to: "devices#update_fcm_token", as: :device_fcm_token
    patch "devices/:id/name", to: "devices#update_name", as: :device_name
    patch "devices/:id/permissions", to: "devices#update_permissions", as: :device_permissions
    get "devices/:id/wallpaper", to: "devices#wallpaper", as: :device_wallpaper
    post "devices/:id/wallpaper", to: "devices#upload_wallpaper", as: :upload_wallpaper
    get "devices/:id/screenshots", to: "devices#screenshots", as: :device_screenshots
    post "devices/:id/screenshots", to: "devices#create_screenshot", as: :device_screenshot_create
    get "devices/:id/wallpapers", to: "devices#wallpapers", as: :device_wallpapers
    delete "devices/:id/wallpapers/:wallpaper_id", to: "devices#destroy_wallpaper", as: :destroy_wallpaper
    get "devices/:id/tasks", to: "devices#tasks", as: :device_tasks
    get "devices/:id/tasks/:task_id", to: "devices#task_detail", as: :device_task
    post "devices/:id/tasks/:task_id/proof", to: "devices#submit_proof", as: :device_task_proof

    get "chaster/lock", to: "chaster#lock", as: :chaster_lock
    get "chaster/locks", to: "chaster#locks", as: :chaster_locks
  end

  # Web upload UI (nickname = beta's nickname)
  get "w/:nickname", to: "wallpaper#show", as: :wallpaper_upload
  get "w/:nickname/upload", to: "wallpaper#upload_new", as: :wallpaper_upload_new
  post "w/:nickname/screenshot_request", to: "wallpaper#screenshot_request", as: :wallpaper_screenshot_request
  post "w/:nickname/grant_permissions_request", to: "wallpaper#grant_permissions_request", as: :wallpaper_grant_permissions_request
  delete "w/:nickname/screenshots/:id", to: "wallpaper#destroy_screenshot", as: :wallpaper_destroy_screenshot
  get "w/:nickname/control/accept", to: "controls#accept_from_link", as: :control_accept_from_link
  post "w/:nickname/control/accept", to: "controls#accept_from_link_submit", as: :control_accept_from_link_submit
  post "w/:nickname", to: "wallpaper#upload", as: :wallpaper_upload_submit
  post "w/:nickname/wallpapers/:wallpaper_id/set_current", to: "wallpaper#set_current", as: :wallpaper_set_current
  delete "w/:nickname/wallpapers/:wallpaper_id", to: "wallpaper#destroy", as: :wallpaper_destroy
  delete "w/:nickname/applications/:id", to: "wallpaper#destroy_application", as: :wallpaper_destroy_application
  delete "w/:nickname/devices/:device_id", to: "wallpaper#destroy_device", as: :wallpaper_destroy_device

  # Tasks
  post "w/:nickname/tasks", to: "tasks#create", as: :wallpaper_tasks
  get "w/:nickname/tasks/:id", to: "tasks#show", as: :wallpaper_task
  post "w/:nickname/tasks/:id/review_proof", to: "tasks#review_proof", as: :wallpaper_task_review_proof
  post "w/:nickname/tasks/:id/punish", to: "tasks#punish", as: :wallpaper_task_punish
  delete "w/:nickname/tasks/:id", to: "tasks#destroy", as: :wallpaper_task_destroy
end
