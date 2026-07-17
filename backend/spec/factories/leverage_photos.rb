# frozen_string_literal: true

FactoryBot.define do
  factory :leverage_photo do
    user
    status { "draft" }
    original_filename { "photo.jpg" }
    drand_rounds { [] }
    tlock_layer_count { 0 }

    trait :with_images do
      after(:build) do |photo|
        photo.original_image.attach(
          io: StringIO.new("fake-original"),
          filename: "original.jpg",
          content_type: "image/jpeg"
        )
        photo.censored_image.attach(
          io: StringIO.new("fake-censored"),
          filename: "censored.jpg",
          content_type: "image/jpeg"
        )
        photo.teaser_image.attach(
          io: StringIO.new("fake-teaser"),
          filename: "teaser.jpg",
          content_type: "image/jpeg"
        )
      end
    end

    trait :without_censor do
      after(:build) do |photo|
        photo.original_image.attach(
          io: StringIO.new("fake-original"),
          filename: "original.jpg",
          content_type: "image/jpeg"
        )
        photo.teaser_image.attach(
          io: StringIO.new("fake-teaser"),
          filename: "teaser.jpg",
          content_type: "image/jpeg"
        )
      end
    end

    trait :active do
      with_images
      status { "active" }
      locked_until { 1.day.from_now }
      initial_duration_seconds { 1.day.to_i }
      drand_rounds { [12_345] }
      drand_chain_hash { LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH }
      tlock_layer_count { 1 }

      after(:build) do |photo|
        photo.original_image.purge if photo.original_image.attached?
        photo.tlock_blob.attach(
          io: StringIO.new("-----BEGIN AGE ENCRYPTED FILE-----\nfake\n-----END AGE ENCRYPTED FILE-----"),
          filename: "layer.tlock",
          content_type: "text/plain"
        )
      end
    end

    trait :unlocked do
      active
      status { "unlocked" }
      locked_until { 1.minute.ago }
    end
  end
end
