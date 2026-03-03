# frozen_string_literal: true

class AdminController < ApplicationController
  def index
    @devices = Device.order(created_at: :desc)
  end
end
