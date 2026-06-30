# frozen_string_literal: true

FactoryBot.define do
  factory :wallpaper_enforcement_config do
    association :user
    enabled { true }
    check_interval_minutes { 60 }
    dismiss_apps_before_capture { true }
    mismatch_delay_minutes { 30 }
    permissions_lost_delay_minutes { 0 }
    app_unreachable_delay_minutes { 0 }
    app_unreachable_threshold_minutes { 120 }
    mismatch_sanction do
      {
        "chaster_add_time_enabled" => true,
        "chaster_seconds" => 3600,
        "chaster_freeze_enabled" => false,
        "pishock_enabled" => false,
        "pishock_intensity" => 50,
        "pishock_duration" => 1
      }
    end
    permissions_lost_sanction do
      {
        "chaster_add_time_enabled" => false,
        "chaster_seconds" => nil,
        "chaster_freeze_enabled" => false,
        "pishock_enabled" => false,
        "pishock_intensity" => 50,
        "pishock_duration" => 1
      }
    end
    app_unreachable_sanction do
      {
        "chaster_add_time_enabled" => false,
        "chaster_seconds" => nil,
        "chaster_freeze_enabled" => false,
        "pishock_enabled" => false,
        "pishock_intensity" => 50,
        "pishock_duration" => 1
      }
    end
  end
end
