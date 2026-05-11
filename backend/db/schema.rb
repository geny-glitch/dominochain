# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_05_11_222500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.text "influencer_names"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "android_version_code"
    t.string "android_apk_url"
  end

  create_table "chaster_locks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "chaster_lock_id", null: false
    t.string "title"
    t.string "status", default: "locked", null: false
    t.datetime "start_date"
    t.datetime "end_date"
    t.boolean "is_frozen", default: false, null: false
    t.datetime "frozen_at"
    t.integer "total_duration"
    t.datetime "unlocked_at"
    t.jsonb "raw_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "chaster_lock_id"], name: "index_chaster_locks_on_user_id_and_chaster_lock_id", unique: true
    t.index ["user_id", "end_date"], name: "index_chaster_locks_on_user_id_and_end_date"
    t.index ["user_id", "status"], name: "index_chaster_locks_on_user_id_and_status"
    t.index ["user_id"], name: "index_chaster_locks_on_user_id"
  end

  create_table "chaster_time_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "chaster_lock_id", null: false
    t.string "source", default: "api", null: false
    t.integer "seconds", null: false
    t.string "summary"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "chaster_lock_id"], name: "index_chaster_time_events_on_user_id_and_chaster_lock_id"
    t.index ["user_id", "occurred_at", "id"], name: "index_chaster_time_events_on_user_id_and_occurred_at_and_id"
    t.index ["user_id"], name: "index_chaster_time_events_on_user_id"
  end

  create_table "cigarette_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "count", default: 1, null: false
    t.date "smoked_on", null: false
    t.datetime "smoked_at", null: false
    t.integer "chaster_seconds", default: 0, null: false
    t.string "chaster_lock_id"
    t.boolean "chaster_applied", default: false, null: false
    t.string "chaster_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "smoked_at"], name: "index_cigarette_entries_on_user_id_and_smoked_at"
    t.index ["user_id", "smoked_on"], name: "index_cigarette_entries_on_user_id_and_smoked_on"
    t.index ["user_id"], name: "index_cigarette_entries_on_user_id"
  end

  create_table "control_requests", force: :cascade do |t|
    t.bigint "beta_id", null: false
    t.bigint "boss_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["beta_id", "boss_id"], name: "index_control_requests_on_beta_id_and_boss_id", unique: true
    t.index ["beta_id"], name: "index_control_requests_on_beta_id"
    t.index ["boss_id"], name: "index_control_requests_on_boss_id"
  end

  create_table "controls", force: :cascade do |t|
    t.bigint "boss_id", null: false
    t.bigint "beta_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["beta_id"], name: "index_controls_on_beta_id", unique: true
    t.index ["boss_id"], name: "index_controls_on_boss_id"
  end

  create_table "device_screenshots", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id", "captured_at"], name: "index_device_screenshots_on_device_id_and_captured_at"
    t.index ["device_id"], name: "index_device_screenshots_on_device_id"
  end

  create_table "devices", force: :cascade do |t|
    t.string "device_id"
    t.string "fcm_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "screen_width"
    t.integer "screen_height"
    t.string "name"
    t.bigint "user_id"
    t.string "auth_token"
    t.boolean "permissions_ok"
    t.datetime "permissions_checked_at"
    t.string "permissions_missing"
    t.index ["auth_token"], name: "index_devices_on_auth_token", unique: true
    t.index ["device_id"], name: "index_devices_on_device_id", unique: true
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "game_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "game_type", default: "snake", null: false
    t.datetime "played_at", null: false
    t.integer "score", default: 0, null: false
    t.string "player_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "game_type"], name: "index_game_sessions_on_user_id_and_game_type"
    t.index ["user_id"], name: "index_game_sessions_on_user_id"
  end

  create_table "influencer_images", force: :cascade do |t|
    t.string "url", null: false
    t.string "name", null: false
    t.string "source", default: "wikimedia", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "likes_count", default: 0, null: false
    t.boolean "hidden", default: false, null: false
    t.integer "dislikes_count", default: 0, null: false
    t.index ["hidden"], name: "index_influencer_images_on_hidden"
    t.index ["name"], name: "index_influencer_images_on_name"
    t.index ["url"], name: "index_influencer_images_on_url", unique: true
  end

  create_table "proof_of_completions", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.text "text"
    t.string "status", default: "pending", null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "review_comment"
    t.index ["status"], name: "index_proof_of_completions_on_status"
    t.index ["task_id"], name: "index_proof_of_completions_on_task_id"
  end

  create_table "punishments", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "created_at"], name: "index_punishments_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_punishments_on_task_id"
  end

  create_table "quiz_questions", force: :cascade do |t|
    t.text "question", null: false
    t.jsonb "answers", default: [], null: false
    t.string "difficulty", null: false
    t.string "category"
    t.string "question_type", default: "normal"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["difficulty"], name: "index_quiz_questions_on_difficulty"
    t.index ["question_type"], name: "index_quiz_questions_on_question_type"
  end

  create_table "showcase_add_time_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "seconds", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "created_at"], name: "index_showcase_add_time_events_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_showcase_add_time_events_on_user_id"
  end

  create_table "showcase_time_additions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "seconds", null: false
    t.string "player_name", null: false
    t.text "message", null: false
    t.boolean "chaster_applied", default: false, null: false
    t.string "chaster_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "created_at"], name: "index_showcase_time_additions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_showcase_time_additions_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "strava_goal_checks", force: :cascade do |t|
    t.bigint "strava_goal_id", null: false
    t.bigint "user_id", null: false
    t.datetime "due_at", null: false
    t.datetime "period_start_at", null: false
    t.datetime "period_end_at", null: false
    t.integer "window_days", null: false
    t.integer "check_time_minutes", null: false
    t.string "time_zone", null: false
    t.integer "required_count", null: false
    t.integer "valid_count", default: 0, null: false
    t.integer "total_count", default: 0, null: false
    t.string "status", null: false
    t.integer "chaster_penalty_seconds", null: false
    t.string "chaster_lock_id"
    t.boolean "chaster_applied", default: false, null: false
    t.string "chaster_error"
    t.jsonb "details", default: {}, null: false
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["strava_goal_id", "due_at"], name: "index_strava_goal_checks_on_strava_goal_id_and_due_at", unique: true
    t.index ["strava_goal_id"], name: "index_strava_goal_checks_on_strava_goal_id"
    t.index ["user_id", "due_at"], name: "index_strava_goal_checks_on_user_id_and_due_at"
    t.index ["user_id"], name: "index_strava_goal_checks_on_user_id"
  end

  create_table "strava_goals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "required_activity_count", default: 1, null: false
    t.integer "window_days", default: 7, null: false
    t.integer "check_time_minutes", default: 0, null: false
    t.string "time_zone", default: "Europe/Paris", null: false
    t.integer "min_duration_seconds"
    t.integer "min_calories"
    t.jsonb "activity_types", default: [], null: false
    t.jsonb "device_names", default: [], null: false
    t.integer "chaster_penalty_seconds", null: false
    t.datetime "last_check_due_at"
    t.datetime "last_check_period_start_at"
    t.datetime "last_check_period_end_at"
    t.integer "last_check_valid_count"
    t.integer "last_check_total_count"
    t.string "last_check_status"
    t.boolean "last_check_chaster_applied", default: false, null: false
    t.string "last_check_chaster_error"
    t.jsonb "last_check_details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "enabled"], name: "index_strava_goals_on_user_id_and_enabled"
    t.index ["user_id"], name: "index_strava_goals_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "expected_proof"
    t.datetime "deadline_at", null: false
    t.boolean "trigger_alarm", default: false, null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "alarm_sound", default: "urgent", null: false
    t.datetime "deleted_at"
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_tasks_on_deleted_at"
    t.index ["user_id", "status"], name: "index_tasks_on_user_id_and_status"
  end

  create_table "users", force: :cascade do |t|
    t.string "nickname", default: "", null: false
    t.string "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "role", default: 0, null: false
    t.string "provider"
    t.string "uid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "chaster_access_token"
    t.string "chaster_refresh_token"
    t.datetime "chaster_token_expires_at"
    t.boolean "pishock_enabled", default: false, null: false
    t.string "pishock_username"
    t.string "pishock_share_code"
    t.string "pishock_api_key"
    t.boolean "showcase_quiz_enabled", default: true, null: false
    t.boolean "showcase_snake_enabled", default: true, null: false
    t.boolean "showcase_backdoor_enabled", default: true, null: false
    t.integer "showcase_snake_seconds_per_fruit", default: 300, null: false
    t.datetime "showcase_snake_seconds_per_fruit_at"
    t.boolean "showcase_dino_enabled", default: true, null: false
    t.integer "showcase_dino_seconds_per_obstacle", default: 300, null: false
    t.datetime "showcase_dino_seconds_per_obstacle_at"
    t.integer "showcase_quiz_seconds_per_point", default: 1, null: false
    t.datetime "showcase_quiz_seconds_per_point_at"
    t.boolean "showcase_tetris_enabled", default: true, null: false
    t.integer "showcase_tetris_seconds_per_line", default: 60, null: false
    t.datetime "showcase_tetris_seconds_per_line_at"
    t.string "puryfi_plugin_token"
    t.jsonb "puryfi_seconds_per_label", default: {}, null: false
    t.float "puryfi_min_score", default: 0.5, null: false
    t.decimal "pishock_intensity_factor", precision: 5, scale: 2, default: "1.0", null: false
    t.string "strava_access_token"
    t.string "strava_refresh_token"
    t.datetime "strava_token_expires_at"
    t.string "strava_athlete_id"
    t.jsonb "beta_ui_prefs", default: {}, null: false
    t.string "uuid", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["nickname"], name: "index_users_on_nickname", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid"
    t.index ["puryfi_plugin_token"], name: "index_users_on_puryfi_plugin_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uuid"], name: "index_users_on_uuid", unique: true
  end

  create_table "wallpaper_applications", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.bigint "wallpaper_id", null: false
    t.datetime "applied_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id", "applied_at"], name: "index_wallpaper_applications_on_device_id_and_applied_at"
    t.index ["device_id"], name: "index_wallpaper_applications_on_device_id"
    t.index ["wallpaper_id"], name: "index_wallpaper_applications_on_wallpaper_id"
  end

  create_table "wallpapers", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "first_downloaded_at"
    t.index ["device_id"], name: "index_wallpapers_on_device_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chaster_locks", "users"
  add_foreign_key "chaster_time_events", "users"
  add_foreign_key "cigarette_entries", "users"
  add_foreign_key "control_requests", "users", column: "beta_id"
  add_foreign_key "control_requests", "users", column: "boss_id"
  add_foreign_key "controls", "users", column: "beta_id"
  add_foreign_key "controls", "users", column: "boss_id"
  add_foreign_key "device_screenshots", "devices"
  add_foreign_key "devices", "users"
  add_foreign_key "game_sessions", "users"
  add_foreign_key "proof_of_completions", "tasks"
  add_foreign_key "punishments", "tasks"
  add_foreign_key "showcase_add_time_events", "users"
  add_foreign_key "showcase_time_additions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "strava_goal_checks", "strava_goals"
  add_foreign_key "strava_goal_checks", "users"
  add_foreign_key "strava_goals", "users"
  add_foreign_key "tasks", "users"
  add_foreign_key "wallpaper_applications", "devices"
  add_foreign_key "wallpaper_applications", "wallpapers"
  add_foreign_key "wallpapers", "devices"
end
