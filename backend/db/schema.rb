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

ActiveRecord::Schema[7.2].define(version: 2026_03_03_150000) do
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
  end

  create_table "devices", force: :cascade do |t|
    t.string "device_id"
    t.string "fcm_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "screen_width"
    t.integer "screen_height"
    t.string "name"
    t.index ["device_id"], name: "index_devices_on_device_id", unique: true
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
    t.index ["status"], name: "index_proof_of_completions_on_status"
    t.index ["task_id"], name: "index_proof_of_completions_on_task_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.bigint "device_id", null: false
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
    t.index ["deleted_at"], name: "index_tasks_on_deleted_at"
    t.index ["device_id", "status"], name: "index_tasks_on_device_id_and_status"
    t.index ["device_id"], name: "index_tasks_on_device_id"
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
  add_foreign_key "proof_of_completions", "tasks"
  add_foreign_key "tasks", "devices"
  add_foreign_key "wallpaper_applications", "devices"
  add_foreign_key "wallpaper_applications", "wallpapers"
  add_foreign_key "wallpapers", "devices"
end
