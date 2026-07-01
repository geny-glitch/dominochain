# frozen_string_literal: true

class RobotsController < ActionController::Base
  def show
    render plain: SearchEngineIndexing.robots_txt_body, content_type: "text/plain"
  end
end
