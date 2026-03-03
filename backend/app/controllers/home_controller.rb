# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    images = InfluencerImage.random_sample(48)
    @tiles = images.map { |img| { name: img.name, url: img.url } }
    @all_urls = @tiles.any? ? InfluencerImage.visible.pluck(:url) : []
  end
end
