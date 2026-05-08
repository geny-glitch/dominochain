# frozen_string_literal: true

module BetaEvents
  module Actions
    class RecordShowcaseLimiterFromEvent < Base
      def call(context)
        ev = context.event
        seconds = ev[:seconds].to_i
        return if seconds <= 0

        ShowcaseAddTimeLimiter.record!(beta_id: context.beta.id, seconds: seconds)
      end
    end
  end
end
