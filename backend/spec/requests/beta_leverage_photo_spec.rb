# frozen_string_literal: true

require "rails_helper"

RSpec.describe BetaLeveragePhotoController, type: :request do
  let(:user) { create(:user, :beta) }

  def jpeg_upload(name)
    file = Tempfile.new([name, ".jpg"])
    file.binmode
    file.write("\xFF\xD8\xFF#{name}")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/jpeg", true, original_filename: "#{name}.jpg")
  end

  before do
    sign_in user
    stub_beta_catalog_feature_flags("beta_action_leverage_photo" => true)
  end

  describe "POST /beta/leverage_photos/upload" do
    it "creates a draft with three images and original filename" do
      post beta_leverage_photo_upload_submit_path, params: {
        original_image: jpeg_upload("vacation"),
        censored_image: jpeg_upload("censored"),
        teaser_image: jpeg_upload("teaser"),
        original_filename: "vacation.png"
      }

      photo = user.leverage_photos.not_deleted.last
      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      expect(photo).to be_draft
      expect(photo.original_filename).to eq("vacation.jpg")
      expect(photo.original_image).to be_attached
      expect(photo.original_image.filename.to_s).to eq("vacation.jpg")
      expect(photo.censored_images.count).to eq(2)
    end

    it "groups several uploads into one bundle" do
      post beta_leverage_photo_upload_submit_path, params: {
        original_image: jpeg_upload("one"),
        teaser_image: jpeg_upload("teaser"),
        original_filename: "one.jpg"
      }
      first = user.leverage_photos.not_deleted.last

      post beta_leverage_photo_upload_submit_path, params: {
        original_image: jpeg_upload("two"),
        teaser_image: jpeg_upload("teaser2"),
        original_filename: "two.jpg",
        bundle_id: first.bundle_id
      }

      expect(user.leverage_photos.not_deleted.count).to eq(2)
      expect(user.leverage_photos.not_deleted.pluck(:bundle_id).uniq.size).to eq(1)
      expect(LeveragePhoto.for_user_list(user).size).to eq(1)
    end

    it "allows multiple photos per user" do
      create(:leverage_photo, :with_images, user: user, original_filename: "one.jpg")

      post beta_leverage_photo_upload_submit_path, params: {
        original_image: jpeg_upload("two"),
        censored_image: jpeg_upload("censored"),
        teaser_image: jpeg_upload("teaser"),
        original_filename: "two.jpg"
      }

      expect(user.leverage_photos.not_deleted.count).to eq(2)
    end

    it "creates a draft with only a preview censored version" do
      post beta_leverage_photo_upload_submit_path, params: {
        original_image: jpeg_upload("vacation"),
        teaser_image: jpeg_upload("teaser"),
        original_filename: "vacation.png"
      }

      photo = user.leverage_photos.not_deleted.last
      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      expect(photo).to be_draft
      expect(photo.original_image).to be_attached
      expect(photo.censored_images.count).to eq(1)
      expect(photo).not_to be_needs_censor
    end
  end

  describe "POST /beta/leverage_photos/:id/censor" do
    it "appends a censored version on a draft" do
      photo = create(:leverage_photo, :without_censor, user: user)

      post beta_leverage_photo_censor_submit_path(photo), params: {
        censored_image: jpeg_upload("censored")
      }

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      photo.reload
      expect(photo.censored_images.count).to eq(2)
      expect(photo).not_to be_needs_censor
    end

    it "appends a version made elsewhere on a locked photo" do
      photo = create(:leverage_photo, :active, user: user)
      count = photo.censored_images.count

      post beta_leverage_photo_censor_submit_path(photo), params: {
        censored_images: [jpeg_upload("elsewhere")]
      }

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      photo.reload
      expect(photo.censored_images.count).to eq(count + 1)
    end

    it "shows an upload form on a locked photo without the original editor" do
      photo = create(:leverage_photo, :active, user: user)

      get beta_leverage_photo_censor_path(photo)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("leverage_photo.censor.upload_title"))
      expect(response.body).to include(%(name="censored_images[]"))
      expect(response.body).not_to include("data-image-editor")
    end
  end

  describe "GET /beta/leverage_photos/:id/original" do
    it "serves original in draft and unlocked with stored original" do
      photo = create(:leverage_photo, :with_images, user: user)

      get beta_leverage_photo_original_path(photo)
      expect(response).to have_http_status(:ok)

      photo.original_image.purge
      photo.tlock_blob.attach(
        io: StringIO.new("tlock"),
        filename: "layer.tlock",
        content_type: "text/plain"
      )
      photo.update!(
        status: "active",
        locked_until: 1.day.from_now,
        drand_rounds: [1],
        tlock_layer_count: 1
      )

      get beta_leverage_photo_original_path(photo)
      expect(response).to have_http_status(:forbidden)

      photo.update!(status: "unlocked", locked_until: 1.minute.ago)
      photo.original_image.attach(
        io: StringIO.new("stored"),
        filename: "stored.jpg",
        content_type: "image/jpeg"
      )

      get beta_leverage_photo_original_path(photo)
      expect(response).to have_http_status(:ok)
    end

    it "does not serve an envelope key stored as the original" do
      photo = create(:leverage_photo, :unlocked, user: user)
      photo.tlock_blob.purge
      photo.original_image.attach(
        io: StringIO.new('{"v":1,"photo_id":15,"alg":"aes-256-gcm","k":"x"}'),
        filename: "photo.jpg",
        content_type: "image/jpeg"
      )

      get beta_leverage_photo_path(photo)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Censored versions are still here")
      expect(response.body).not_to include(">#{I18n.t("leverage_photo.show.download_original")}<")

      get beta_leverage_photo_original_path(photo)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /beta/leverage_photos/:id/restore_original" do
    it "persists decrypted original on unlocked photo" do
      photo = create(:leverage_photo, :unlocked, user: user)

      post beta_leverage_photo_restore_original_path(photo), params: {
        original_image: jpeg_upload("restored")
      }

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      photo.reload
      expect(photo.original_image).to be_attached
      expect(photo.tlock_blob).not_to be_attached
    end

    it "restores an envelope lock from the server without an uploaded original" do
      photo = create(:leverage_photo, :with_images, user: user)
      captured = {}
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes) do |bytes, _|
        captured[:payload] = bytes
        { armored: "AGE-KEY", round: 11, chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH }
      end
      LeveragePhotos::StartTimerServer.new(photo: photo, duration_seconds: 3600).call!
      photo.update!(status: "unlocked", locked_until: 1.minute.ago)
      allow(LeveragePhotos::TlockCrypto).to receive(:decrypt_attachment).and_return(captured[:payload])

      post beta_leverage_photo_restore_original_path(photo)

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      photo.reload
      expect(photo.original_image.download).to eq("fake-original")
      expect(photo.tlock_blob).not_to be_attached
      expect(photo.encrypted_original).not_to be_attached
    end
  end

  describe "DELETE /beta/leverage_photos/:id/original" do
    it "sanctions photo by removing original only" do
      photo = create(:leverage_photo, :with_images, user: user)

      delete beta_leverage_photo_delete_original_path(photo)

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      photo.reload
      expect(photo).to be_sanctioned
      expect(photo.original_image).not_to be_attached
      expect(photo.censored_images).to be_attached
    end

    it "rejects when no censored version exists" do
      photo = create(:leverage_photo, :without_censor, user: user)
      photo.censored_images.purge

      delete beta_leverage_photo_delete_original_path(photo)

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      expect(flash[:alert]).to be_present
      expect(photo.reload).to be_draft
    end
  end

  describe "POST /beta/leverage_photos/:id/start" do
    def stub_server_lock!(round: 99_001, wrap_round: 88_888)
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
        armored: "AGE-KEY",
        round: round,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment).and_return(
        armored: "WRAPPED",
        round: wrap_round,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )
    end

    it "activates photo, stores tlock blob, and purges original" do
      photo = create(:leverage_photo, :with_images, user: user)
      stub_server_lock!

      post beta_leverage_photo_start_path(photo),
        params: { duration_seconds: 2.hours.to_i },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo).to be_active
      expect(photo.original_image).not_to be_attached
      expect(photo.tlock_blob).to be_attached
      expect(photo.encrypted_original).to be_attached
      expect(photo.tlock_format).to eq("envelope")
      expect(photo.drand_rounds).to eq([99_001])
      expect(photo.tlock_layer_count).to eq(1)
    end

    it "re-locks an unlocked photo with a fresh timer" do
      photo = create(:leverage_photo, :unlocked, user: user)
      photo.leverage_photo_extensions.create!(
        added_seconds: 3600,
        locked_until_before: 1.day.from_now,
        locked_until_after: 1.day.from_now + 1.hour,
        drand_round_added: 12_346
      )
      stub_server_lock!(wrap_round: 88_888)

      post beta_leverage_photo_start_path(photo),
        params: { duration_seconds: 2.hours.to_i },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo).to be_active
      expect(photo.original_image).not_to be_attached
      expect(photo.tlock_blob).to be_attached
      expect(photo.tlock_blob.download).to eq("AGE-KEY")
      expect(photo.tlock_format).to eq("envelope")
      expect(photo.encrypted_original).to be_attached
      expect(photo.drand_rounds).to eq([99_001])
      expect(photo.tlock_layer_count).to eq(1)
      expect(photo.leverage_photo_extensions.count).to eq(0)
    end

    it "forbids start when photo is active" do
      photo = create(:leverage_photo, :active, user: user)

      post beta_leverage_photo_start_path(photo),
        params: { duration_seconds: 2.hours.to_i },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /beta/leverage_photos/:id/add_time" do
    def stub_wrap!(round:)
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
        armored: "AGE-KEY",
        round: round,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment).and_return(
        armored: "OUTER",
        round: round,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )
    end

    it "nests a new tlock layer" do
      photo = create(:leverage_photo, :active, user: user)
      stub_wrap!(round: 200_000)

      post beta_leverage_photo_add_time_path(photo),
        params: { added_seconds: 3.hours.to_i },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo.tlock_layer_count).to eq(1)
      expect(photo.tlock_format).to eq("envelope")
      expect(photo.encrypted_original).to be_attached
      expect(photo.drand_rounds).to eq([12_345, 200_000])
      expect(photo.leverage_photo_extensions.count).to eq(1)
    end

    it "saves the current duration as the add-time base" do
      photo = create(:leverage_photo, :active, user: user)
      stub_wrap!(round: 200_001)

      post beta_leverage_photo_add_time_path(photo),
        params: {
          added_seconds: 3.days.to_i,
          save_as_base: true,
          apply_next_step: true
        },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo.add_time_base_seconds).to eq(3.days.to_i)
      expect(photo.add_time_step_n).to eq(1)
    end

    it "increments the stored multiplier on the next step" do
      photo = create(:leverage_photo, :active, user: user, add_time_base_seconds: 3.days.to_i, add_time_step_n: 1)
      stub_wrap!(round: 200_002)

      post beta_leverage_photo_add_time_path(photo),
        params: {
          added_seconds: 6.days.to_i,
          apply_next_step: true
        },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo.add_time_base_seconds).to eq(3.days.to_i)
      expect(photo.add_time_step_n).to eq(2)
    end
  end

  describe "GET /beta/leverage_photos/:id/decrypt_payload" do
    it "forbids while active before unlock and allows after unlock" do
      photo = create(:leverage_photo, :active, user: user, locked_until: 1.day.from_now)

      get beta_leverage_photo_decrypt_payload_path(photo)
      expect(response).to have_http_status(:forbidden)

      photo.update!(locked_until: 1.minute.ago)
      get beta_leverage_photo_decrypt_payload_path(photo)
      expect(response).to have_http_status(:ok)
      expect(photo.reload).to be_unlocked
    end
  end

  describe "DELETE /beta/leverage_photos/:id" do
    it "permanently deletes the photo" do
      photo = create(:leverage_photo, :with_images, user: user)
      delete beta_leverage_photo_destroy_path(photo)
      expect(response).to redirect_to(beta_actions_leverage_photo_path)
      expect(photo.reload).to be_deleted
    end
  end

  describe "GET /beta/leverage_photos/:id" do
    it "shows a large censored hero, keeps censored thumbs, and recaps added time" do
      photo = create(:leverage_photo, :active, user: user, initial_duration_seconds: 1.day.to_i)
      photo.leverage_photo_extensions.create!(
        added_seconds: 3600,
        locked_until_before: photo.locked_until,
        locked_until_after: photo.locked_until + 1.hour,
        drand_round_added: 88_001
      )

      get beta_leverage_photo_path(photo)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ds-beta-leverage-hero")
      expect(response.body).to include("censored.jpg")
      expect(response.body).to include("teaser.jpg")
      expect(response.body).to include("ds-beta-leverage-reminders--thumbs")
      expect(response.body).to include(I18n.t("leverage_photo.show.time_history.title"))
      expect(response.body).to include("Started with 1 day")
      expect(response.body).to include("+ 1 hour")
      expect(response.body).to include("Total 1 day 1 hour")
      expect(response.body.index("data-action=\"add-time\"")).to be < response.body.index(
        I18n.t("leverage_photo.show.time_history.title")
      )
      expect(response.body).to include("data-duration-unit")
      expect(response.body).to include(%(value="days" selected))
      expect(response.body).to include("data-action=\"add-time-step\"")
      expect(response.body).to include("data-save-as-base")
      expect(response.body).not_to include("ds-beta-leverage-duration-shortcuts")
      expect(response.body).to include(I18n.t("leverage_photo.censor.upload_label"))
      expect(response.body).to include(%(name="censored_images[]"))
    end

    it "labels the next step from the saved base, not the last add" do
      photo = create(
        :leverage_photo,
        :active,
        user: user,
        add_time_base_seconds: 3.days.to_i,
        add_time_step_n: 1
      )

      get beta_leverage_photo_path(photo)

      expect(response.body).to include("Add 2 × 3 days")
    end

    it "defaults a new lock duration to days" do
      photo = create(:leverage_photo, :with_images, user: user)

      get beta_leverage_photo_path(photo)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(value="days" selected))
      expect(response.body).to include(%(id="lp-#{photo.id}-duration-minutes"))
      expect(response.body).to match(/id="lp-#{photo.id}-duration-minutes"[^>]*value="1"/)
    end
  end

  describe "GET /beta/leverage_photos/random" do
    it "opens a random photo" do
      photo = create(:leverage_photo, :with_images, user: user)

      get beta_leverage_photo_random_path

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
    end

    it "alerts when there are no photos" do
      get beta_leverage_photo_random_path

      expect(response).to redirect_to(beta_actions_leverage_photo_path)
      expect(flash[:alert]).to eq(I18n.t("flash.beta.leverage_photo.none_available"))
    end
  end

  describe "blind add" do
    it "links random open and blind add from the photos page" do
      get beta_actions_leverage_photo_path

      expect(response.body).to include(I18n.t("leverage_photo.index.random"))
      expect(response.body).to include(I18n.t("leverage_photo.blind.title"))
      expect(response.body).to include(beta_leverage_photo_random_path)
      expect(response.body).to include(beta_leverage_photo_blind_path)
    end

    it "keeps the same photo across lock submissions and records session time" do
      photo = create(:leverage_photo, :with_images, user: user)
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
        armored: "AGE-KEY",
        round: 99_001,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )

      post beta_leverage_photo_blind_pick_path
      expect(session[:leverage_blind_game]["photo_id"]).to eq(photo.id)

      post beta_leverage_photo_blind_lock_path,
        params: {
          duration_seconds: 2.hours.to_i,
          save_as_base: true
        },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "ok")
      expect(response.parsed_body).not_to have_key("locked_until")
      expect(session[:leverage_blind_game]["photo_id"]).to eq(photo.id)
      expect(session[:leverage_blind_game]["added_seconds"]).to eq(2.hours.to_i)
      expect(photo.reload).to be_active
    end

    it "extends an already locked photo without showing lock status" do
      photo = create(
        :leverage_photo,
        :active,
        user: user,
        original_filename: "secret-vacation.jpg",
        locked_until: Time.zone.local(2026, 12, 1, 12, 0, 0)
      )

      post beta_leverage_photo_blind_pick_path
      get beta_leverage_photo_blind_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("leverage_photo.blind.placeholder"))
      expect(response.body).to include(I18n.t("leverage_photo.show.add_time"))
      expect(response.body).to include("data-save-as-base")
      expect(response.body).to include("data-action=\"add-time-step\"")
      expect(response.body).not_to include(photo.original_filename)
      expect(response.body).not_to include(I18n.t("leverage_photo.status.active"))
      expect(response.body).not_to include(I18n.t("leverage_photo.show.time_history.title"))
      expect(response.body).not_to include("ds-beta-leverage-panel__countdown")
      expect(response.body).not_to include(I18n.l(photo.locked_until, format: :lock_until))
      expect(response.body).not_to include(beta_leverage_photo_path(photo))

      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_bytes).and_return(
        armored: "AGE-KEY",
        round: 200_000,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )
      allow(LeveragePhotos::TlockCrypto).to receive(:encrypt_attachment).and_return(
        armored: "OUTER",
        round: 200_000,
        chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      )

      post beta_leverage_photo_blind_lock_path,
        params: { added_seconds: 3.hours.to_i },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(photo.reload.tlock_layer_count).to eq(1)
      expect(session[:leverage_blind_game]["added_seconds"]).to eq(3.hours.to_i)

      get beta_leverage_photo_blind_path
      expect(response.body).to include(I18n.t("leverage_photo.blind.added_this_round", duration: "3 hours"))
      expect(response.body).not_to include(I18n.t("leverage_photo.status.active"))
    end

    it "hides the preview until reveal and never serves the original there" do
      photo = create(:leverage_photo, :active, user: user)

      post beta_leverage_photo_blind_pick_path
      get beta_leverage_photo_blind_preview_path
      expect(response).to have_http_status(:forbidden)

      post beta_leverage_photo_blind_reveal_path
      get beta_leverage_photo_blind_path
      expect(response.body).to include(beta_leverage_photo_blind_preview_path)
      expect(response.body).to include(beta_leverage_photo_path(photo))
      expect(response.body).to include(I18n.t("leverage_photo.blind.open_photo"))
      expect(response.body).not_to include(beta_leverage_photo_original_path(photo))

      get beta_leverage_photo_blind_preview_path
      expect(response).to have_http_status(:ok)
    end

    it "requires a picked photo before locking" do
      post beta_leverage_photo_blind_lock_path,
        params: { duration_seconds: 3600 },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("flash.beta.leverage_photo.blind_need_pick"))
    end
  end

  describe "GET /beta/actions/leverage_photo" do
    it "uses the higher-definition censored preview and a compact lock date" do
      photo = create(:leverage_photo, :active, user: user, locked_until: Time.zone.local(2026, 9, 28, 19, 9, 43))

      get beta_actions_leverage_photo_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("censored.jpg")
      expect(response.body).not_to include("teaser.jpg")
      expect(response.body).to include("🔒 28-09-2026 19:09")
      expect(response.body).not_to include("Locked until")
    end

    it "sorts by soonest unlock by default and can reverse" do
      later = create(
        :leverage_photo,
        :active,
        user: user,
        original_filename: "later.jpg",
        locked_until: 3.days.from_now
      )
      sooner = create(
        :leverage_photo,
        :active,
        user: user,
        original_filename: "sooner.jpg",
        locked_until: 1.hour.from_now
      )

      get beta_actions_leverage_photo_path
      expect(response.body).to include(I18n.t("leverage_photo.index.sort_unlock_soonest"))
      expect(response.body.index("sooner.jpg")).to be < response.body.index("later.jpg")

      get beta_actions_leverage_photo_path, params: { sort: "unlock_desc" }
      expect(response.body.index("later.jpg")).to be < response.body.index("sooner.jpg")
    end
  end

  describe "GET /beta" do
    it "uses the higher-definition censored preview and a compact lock date" do
      user.update!(
        beta_ui_prefs: {
          "catalog_visibility" => { "actions" => { "leverage_photo" => true } }
        }
      )
      create(:leverage_photo, :active, user: user, locked_until: Time.zone.local(2026, 9, 28, 19, 9, 43))

      get beta_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("censored.jpg")
      expect(response.body).not_to include("teaser.jpg")
      expect(response.body).to include("🔒 28-09-2026 19:09")
      expect(response.body).not_to include("Locked until")
    end
  end
end
