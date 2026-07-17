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

  def tlock_upload(content)
    file = Tempfile.new(["layer", ".tlock"])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/plain", false, original_filename: "layer.tlock")
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
      expect(photo.censored_image).to be_attached
      expect(photo.teaser_image).to be_attached
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

    it "creates a draft without censored image" do
      post beta_leverage_photo_upload_submit_path, params: {
        original_image: jpeg_upload("vacation"),
        teaser_image: jpeg_upload("teaser"),
        original_filename: "vacation.png"
      }

      photo = user.leverage_photos.not_deleted.last
      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      expect(photo).to be_draft
      expect(photo.original_image).to be_attached
      expect(photo.teaser_image).to be_attached
      expect(photo.censored_image).not_to be_attached
      expect(photo).to be_needs_censor
    end
  end

  describe "POST /beta/leverage_photos/:id/censor" do
    it "attaches censored reminder on a draft" do
      photo = create(:leverage_photo, :without_censor, user: user)

      post beta_leverage_photo_censor_submit_path(photo), params: {
        censored_image: jpeg_upload("censored")
      }

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      photo.reload
      expect(photo.censored_image).to be_attached
      expect(photo.teaser_image).to be_attached
      expect(photo).not_to be_needs_censor
    end

    it "forbids censor after timer start" do
      photo = create(:leverage_photo, :active, user: user)

      post beta_leverage_photo_censor_submit_path(photo), params: {
        censored_image: jpeg_upload("censored")
      }

      expect(response).to redirect_to(beta_leverage_photo_path(photo))
      expect(flash[:alert]).to be_present
    end
  end

  describe "GET /beta/leverage_photos/:id/original" do
    it "serves original in draft and forbids after start" do
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
    end
  end

  describe "POST /beta/leverage_photos/:id/start" do
    it "activates photo, stores tlock blob, and purges original" do
      photo = create(:leverage_photo, :with_images, user: user)
      locked_until = 2.hours.from_now

      post beta_leverage_photo_start_path(photo),
        params: {
          tlock_blob: tlock_upload("AGE"),
          drand_round: 99_001,
          duration_seconds: 2.hours.to_i,
          locked_until: locked_until.iso8601,
          drand_chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
        },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo).to be_active
      expect(photo.original_image).not_to be_attached
      expect(photo.tlock_blob).to be_attached
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
      locked_until = 2.hours.from_now

      post beta_leverage_photo_start_path(photo),
        params: {
          tlock_blob: tlock_upload("NEW-AGE"),
          drand_round: 88_888,
          duration_seconds: 2.hours.to_i,
          locked_until: locked_until.iso8601,
          drand_chain_hash: LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
        },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo).to be_active
      expect(photo.original_image).not_to be_attached
      expect(photo.tlock_blob).to be_attached
      expect(photo.tlock_blob.download).to eq("NEW-AGE")
      expect(photo.drand_rounds).to eq([88_888])
      expect(photo.tlock_layer_count).to eq(1)
      expect(photo.leverage_photo_extensions.count).to eq(0)
    end

    it "forbids start when photo is active" do
      photo = create(:leverage_photo, :active, user: user)

      post beta_leverage_photo_start_path(photo),
        params: {
          tlock_blob: tlock_upload("AGE"),
          drand_round: 99_001,
          duration_seconds: 2.hours.to_i,
          locked_until: 2.hours.from_now.iso8601
        },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /beta/leverage_photos/:id/add_time" do
    it "nests a new tlock layer" do
      photo = create(:leverage_photo, :active, user: user)
      new_until = photo.locked_until + 3.hours

      post beta_leverage_photo_add_time_path(photo),
        params: {
          tlock_blob: tlock_upload("OUTER"),
          drand_round: 200_000,
          added_seconds: 3.hours.to_i,
          locked_until: new_until.iso8601
        },
        headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      photo.reload
      expect(photo.tlock_layer_count).to eq(2)
      expect(photo.drand_rounds).to eq([12_345, 200_000])
      expect(photo.leverage_photo_extensions.count).to eq(1)
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
      expect(response).to redirect_to(beta_leverage_photos_path)
      expect(photo.reload).to be_deleted
    end
  end
end
