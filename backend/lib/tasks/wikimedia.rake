# frozen_string_literal: true

namespace :wikimedia do
  desc "Fetch 10 images per star from Wikimedia and store in DB"
  task fetch_images: :environment do
    names = AppSetting.instance.influencer_names_list
    puts "Fetching #{WikimediaCommonsService::IMAGES_PER_STAR} images per star for #{names.size} names..."

    names.each_with_index do |name, i|
      count = WikimediaCommonsService.fetch_and_store_for_name(name).size
      puts "  #{i + 1}/#{names.size} #{name}: #{count} images"
      sleep 0.3 # Be nice to the API
    end

    total = InfluencerImage.count
    puts "Done. #{total} images in DB."
  end
end
