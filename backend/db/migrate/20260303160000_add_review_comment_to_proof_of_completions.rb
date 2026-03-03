# frozen_string_literal: true

class AddReviewCommentToProofOfCompletions < ActiveRecord::Migration[7.2]
  def change
    add_column :proof_of_completions, :review_comment, :text
  end
end
