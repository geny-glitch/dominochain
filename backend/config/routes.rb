Rails.application.routes.draw do
  get "robots.txt", to: "robots#show"

  patch "locale", to: "locales#update", as: :user_locale

  devise_for :users, path: "", path_names: {
    sign_in: "login", sign_out: "logout", sign_up: "signup"
  }, controllers: {
    registrations: "registrations",
    sessions: "sessions",
    passwords: "passwords",
    confirmations: "confirmations",
    unlocks: "unlocks"
  }

  devise_scope :user do
    get "signup/boss", to: "boss_registrations#new", as: :new_boss_registration
    post "signup/boss", to: "boss_registrations#create", as: :boss_registration
  end

  get "dashboard", to: "dashboard#show", as: :dashboard
  get "beta", to: "beta_dashboard#home", as: :beta_dashboard
  get "beta/scenarios", to: "beta_dashboard#scenarios", as: :beta_scenarios
  post "beta/scenarios", to: "beta_dashboard#create_scenario", as: :beta_scenarios_create
  get "beta/sources/puryfi", to: "beta_dashboard#sources_puryfi", as: :beta_sources_puryfi
  get "beta/sources/cigarettes", to: "beta_dashboard#sources_cigarettes", as: :beta_sources_cigarettes
get "beta/sources/strava", to: "beta_dashboard#sources_strava", as: :beta_sources_strava
get "beta/sources/vitrine", to: "beta_dashboard#sources_showcase", as: :beta_sources_showcase
  get "beta/sources/wallpaper", to: "beta_dashboard#sources_wallpaper", as: :beta_sources_wallpaper
  get "beta/sources/cornertime", to: "beta_dashboard#sources_cornertime", as: :beta_sources_cornertime
  patch "beta/cornertime/config", to: "beta_dashboard#update_cornertime_config", as: :beta_cornertime_config
  patch "beta/strava/config", to: "beta_dashboard#update_strava_config", as: :beta_strava_config
  get "cornertime/session", to: "cornertime_sessions#show", as: :cornertime_session
  post "cornertime/session", to: "cornertime_sessions#create"
  patch "cornertime/session/:id/stop", to: "cornertime_sessions#stop", as: :cornertime_session_stop
  post "cornertime/session/:id/violations", to: "cornertime_sessions#create_violation", as: :cornertime_session_violations
  get "beta/leverage_photos", to: "beta_leverage_photo#index", as: :beta_leverage_photos
  get "beta/leverage_photos/upload", to: "beta_leverage_photo#upload_new", as: :beta_leverage_photo_upload
  post "beta/leverage_photos/upload", to: "beta_leverage_photo#upload", as: :beta_leverage_photo_upload_submit
  get "beta/leverage_photos/:id", to: "beta_leverage_photo#show", as: :beta_leverage_photo
  get "beta/leverage_photos/:id/original", to: "beta_leverage_photo#original", as: :beta_leverage_photo_original
  get "beta/leverage_photos/:id/censor", to: "beta_leverage_photo#censor_new", as: :beta_leverage_photo_censor
  post "beta/leverage_photos/:id/censor", to: "beta_leverage_photo#censor", as: :beta_leverage_photo_censor_submit
  post "beta/leverage_photos/:id/start", to: "beta_leverage_photo#start", as: :beta_leverage_photo_start
  post "beta/leverage_photos/:id/add_time", to: "beta_leverage_photo#add_time", as: :beta_leverage_photo_add_time
  post "beta/leverage_photos/:id/set_as_wallpaper", to: "beta_leverage_photo#set_as_wallpaper", as: :beta_leverage_photo_set_as_wallpaper
  get "beta/leverage_photos/:id/tlock_blob", to: "beta_leverage_photo#tlock_blob", as: :beta_leverage_photo_tlock_blob
  get "beta/leverage_photos/:id/decrypt_payload", to: "beta_leverage_photo#decrypt_payload", as: :beta_leverage_photo_decrypt_payload
  delete "beta/leverage_photos/:id", to: "beta_leverage_photo#destroy", as: :beta_leverage_photo_destroy
  get "beta/leverage_photo", to: redirect("/beta/leverage_photos")
  patch "beta/wallpaper/enforcement", to: "beta_dashboard#update_wallpaper_enforcement", as: :beta_wallpaper_enforcement
  post "beta/wallpaper/enforcement/test", to: "beta_dashboard#test_wallpaper_enforcement_check", as: :beta_wallpaper_enforcement_test
  get "beta/wallpaper/upload", to: "beta_wallpaper#upload", as: :beta_wallpaper_upload
  post "beta/wallpaper/upload", to: "beta_wallpaper#create", as: :beta_wallpaper_create
  get "beta/actions/chaster", to: "beta_dashboard#actions_chaster", as: :beta_actions_chaster
  get "beta/actions/pishock", to: "beta_dashboard#actions_pishock", as: :beta_actions_pishock
  get "beta/actions/leverage_photo", to: "beta_dashboard#actions_leverage_photo", as: :beta_actions_leverage_photo
  get "beta/sources/leverage_photo", to: redirect("/beta/actions/leverage_photo")
  get "beta/reglages", to: "beta_dashboard#settings", as: :beta_settings
  patch "beta/catalogue/visibility", to: "beta_dashboard#update_catalog_visibility", as: :beta_catalog_visibility
  get "beta/compte", to: "beta_dashboard#account", as: :beta_account
  patch "beta/pishock", to: "beta_dashboard#update_pishock", as: :beta_pishock
  post "beta/pishock/test", to: "beta_dashboard#test_pishock", as: :beta_pishock_test
  get "beta/pishock/debug", to: "pishock_debug#show", as: :beta_pishock_debug
  patch "beta/backdoor", to: "beta_dashboard#update_backdoor", as: :beta_backdoor
  patch "beta/public_boss", to: "beta_dashboard#update_public_boss", as: :beta_public_boss
  patch "beta/snake_seconds", to: "beta_dashboard#update_snake_seconds", as: :beta_snake_seconds
  patch "beta/puryfi", to: "beta_dashboard#update_puryfi", as: :beta_puryfi
  post "beta/puryfi/regenerate_token", to: "beta_dashboard#regenerate_puryfi_token", as: :beta_puryfi_regenerate_token
  post "beta/pishock/debug/step1", to: "pishock_debug#step1", as: :beta_pishock_debug_step1
  post "beta/pishock/debug/step2", to: "pishock_debug#step2", as: :beta_pishock_debug_step2
  post "beta/pishock/debug/step3", to: "pishock_debug#step3", as: :beta_pishock_debug_step3
  post "beta/pishock/debug/step4", to: "pishock_debug#step4", as: :beta_pishock_debug_step4
  post "beta/pishock/debug/clear", to: "pishock_debug#clear", as: :beta_pishock_debug_clear

  # Public read-only boss view (no authentication)
  get "watch/:nickname", to: "public_boss#show", as: :public_boss
  get "watch/:nickname/upload", to: "public_boss#upload_new", as: :public_boss_upload_new
  post "watch/:nickname/screenshot_request", to: "public_boss#screenshot_request", as: :public_boss_screenshot_request
  post "watch/:nickname/wallpapers/:wallpaper_id/set_current", to: "public_boss#set_current", as: :public_boss_set_current
  post "watch/:nickname", to: "public_boss#upload", as: :public_boss_upload

  # Vitrine du beta (page publique)
  get "showcase/:nickname", to: "showcase#show", as: :showcase
  get "showcase/:nickname/quiz", to: "showcase#quiz", as: :showcase_quiz
  get "showcase/:nickname/snake", to: "showcase#snake", as: :showcase_snake
  get "showcase/:nickname/dino", to: "showcase#dino", as: :showcase_dino
  get "showcase/:nickname/tetris", to: "showcase#tetris", as: :showcase_tetris
  get "showcase/:nickname/backdoor", to: "showcase#backdoor", as: :showcase_backdoor
  get "showcase/:nickname/backdoor/lock", to: "showcase#backdoor_chaster_lock", as: :showcase_backdoor_lock
  post "showcase/:nickname/backdoor/add_time", to: "showcase#backdoor_add_time", as: :showcase_backdoor_add_time
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
  # Strava OAuth + beta weekly goals
  get "strava/connect", to: "strava#connect", as: :strava_connect
  get "strava/callback", to: "strava#callback", as: :strava_callback
  delete "strava/disconnect", to: "strava#disconnect", as: :strava_disconnect
  post "beta/strava/goals", to: "strava#create_goal", as: :beta_strava_goals
  patch "beta/strava/goals/:id", to: "strava#update_goal", as: :beta_strava_goal
  delete "beta/strava/goals/:id", to: "strava#destroy_goal", as: :beta_strava_goal_destroy
  post "beta/strava/goals/:id/check", to: "strava#check_goal", as: :beta_strava_goal_check
  get "beta/tasks/:id", to: "beta_dashboard#task", as: :beta_task
  post "beta/tasks/:id/proof", to: "beta_dashboard#submit_proof", as: :beta_task_proof
  post "control/release", to: "controls#release", as: :control_release
  post "control/accept_request", to: "controls#accept_request", as: :control_accept_request
  post "control/reject_request", to: "controls#reject_request", as: :control_reject_request

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  get "terms", to: "terms#show", as: :terms

  root "home#index"

  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  # Admin
  get "admin", to: "admin#index", as: :admin
  get "admin/settings", to: "admin#settings", as: :admin_settings
  patch "admin/settings", to: "admin#update_settings", as: :admin_update_settings
  post "admin/controls/:control_id/release", to: "admin#release_control", as: :admin_release_control
  post "admin/feature_flags_cache/invalidate", to: "admin#invalidate_feature_flags_cache", as: :admin_invalidate_feature_flags_cache
  get "admin/review", to: "admin#review", as: :admin_review
  get "admin/review/images", to: "admin#review_images", as: :admin_review_images
  post "admin/review/images/:id/like", to: "admin#review_like", as: :admin_review_like
  post "admin/review/images/:id/dislike", to: "admin#review_dislike", as: :admin_review_dislike
  get "admin/wallpaper_pairs", to: "admin#wallpaper_pairs", as: :admin_wallpaper_pairs
  post "admin/wallpaper_pairs/export_disagreements", to: "admin#wallpaper_pairs_export_disagreements", as: :admin_wallpaper_pairs_export_disagreements
  post "admin/wallpaper_pairs/:id/review", to: "admin#wallpaper_pair_review", as: :admin_wallpaper_pair_review
  post "admin/wallpaper_pairs/:id/run_algorithm", to: "admin#wallpaper_pair_run_algorithm", as: :admin_wallpaper_pair_run_algorithm

  get  "android/version", to: "android_version#show"
  get  "android/app.apk", to: "android_version#apk"
  post "android/version", to: "android_version#update"

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
    get "chaster/time_events", to: "chaster#time_events", as: :chaster_time_events
    post "chaster/add_time", to: "chaster#add_time", as: :chaster_add_time

    get "cigarettes", to: "cigarette_entries#index"
    post "cigarettes", to: "cigarette_entries#create"

    get "cornertime/config", to: "cornertime/configs#show"
    post "cornertime/sessions", to: "cornertime/sessions#create"
    patch "cornertime/sessions/:id/stop", to: "cornertime/sessions#stop"
    post "cornertime/sessions/:id/violations", to: "cornertime/violations#create"

    get "showcase_settings", to: "showcase_settings#show"
    patch "showcase_settings", to: "showcase_settings#update"
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
