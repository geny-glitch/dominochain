# frozen_string_literal: true

namespace :previews do
  desc "Backfill boss UI preview variants for wallpapers and screenshots (ASYNC=false to process inline)"
  task backfill: :environment do
    async = ENV["ASYNC"] != "false"
    ImagePreviewVariant.backfill!(async: async)
  end
end
