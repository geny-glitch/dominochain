# frozen_string_literal: true

class Control < ApplicationRecord
  belongs_to :boss, class_name: "User"
  belongs_to :beta, class_name: "User"

  enum status: { pending: 0, accepted: 1, released: 2 }

  validates :beta_id, uniqueness: true
end
