# frozen_string_literal: true

namespace :chess_com do
  desc "Check due Chess.com ELO goals (prod: Solid Queue recurring task in config/recurring.yml)"
  task check_due_goals: :environment do
    ChessComGoalCheckJob.perform_now
  end
end
