# frozen_string_literal: true

FactoryBot.define do
  factory :wallpaper_enforcement_config do
    association :user
    enabled { true }
    check_interval_minutes { 60 }
    dismiss_apps_before_capture { true }
    mismatch_add_time_delay_minutes { 30 }
    mismatch_freeze_delay_minutes { 60 }
    app_unreachable_threshold_minutes { 120 }
    mismatch_add_time_sanction do
      { "action" => "chaster_add_time", "chaster_seconds" => 3600, "pishock_intensity" => 50, "pishock_duration" => 1 }
    end
    mismatch_freeze_sanction do
      { "action" => "none", "chaster_seconds" => 3600, "pishock_intensity" => 50, "pishock_duration" => 1 }
    end
    permissions_lost_sanction do
      { "action" => "none", "chaster_seconds" => 3600, "pishock_intensity" => 50, "pishock_duration" => 1 }
    end
    app_unreachable_sanction do
      { "action" => "none", "chaster_seconds" => 3600, "pishock_intensity" => 50, "pishock_duration" => 1 }
    end
  end
end
