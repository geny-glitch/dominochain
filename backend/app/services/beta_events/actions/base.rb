# frozen_string_literal: true

module BetaEvents
  module Actions
    class Base
      def call(context)
        raise NotImplementedError
      end
    end
  end
end
