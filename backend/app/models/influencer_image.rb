# frozen_string_literal: true

class InfluencerImage < ApplicationRecord
  validates :url, presence: true, uniqueness: true
  validates :name, presence: true
  validates :source, presence: true

  scope :visible, -> { where(hidden: false) }
  scope :random, -> { order(Arel.sql("RANDOM()")) }

  def self.random_sample(limit = 48)
    visible.random.limit(limit)
  end

  def like!
    increment!(:likes_count)
  end

  def hide!
    update!(hidden: true)
  end
end
