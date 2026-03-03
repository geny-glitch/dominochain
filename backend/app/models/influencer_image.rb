# frozen_string_literal: true

class InfluencerImage < ApplicationRecord
  validates :url, presence: true, uniqueness: true
  validates :name, presence: true
  validates :source, presence: true

  scope :visible, -> { where(hidden: false) }
  scope :positive_score, -> { where("likes_count >= dislikes_count") }
  scope :random, -> { order(Arel.sql("RANDOM()")) }

  def self.random_sample(limit = 48)
    visible.positive_score.random.limit(limit)
  end

  def like!
    increment!(:likes_count)
  end

  def dislike!
    increment!(:dislikes_count)
  end

  def hide!
    update!(hidden: true)
  end
end
