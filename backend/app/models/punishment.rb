# frozen_string_literal: true

class Punishment < ApplicationRecord
  belongs_to :task

  validates :task_id, presence: true
end
