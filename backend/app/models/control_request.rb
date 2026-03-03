# frozen_string_literal: true

class ControlRequest < ApplicationRecord
  belongs_to :beta, class_name: "User"
  belongs_to :boss, class_name: "User"

  enum status: { pending: 0, accepted: 1, rejected: 2 }
end
