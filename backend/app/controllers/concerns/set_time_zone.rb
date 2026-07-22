# frozen_string_literal: true

module SetTimeZone
  extend ActiveSupport::Concern

  included do
    around_action :use_user_time_zone
  end

  private

  def use_user_time_zone(&block)
    zone =
      if user_signed_in?
        current_user.time_zone_object
      else
        Time.find_zone(Rails.application.config.time_zone) || Time.zone
      end

    Time.use_zone(zone, &block)
  end
end
