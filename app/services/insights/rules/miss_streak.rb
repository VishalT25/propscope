module Insights
  module Rules
    # "X has failed to exceed 24.5 points in 6 straight games." Backs the Under.
    class MissStreak < Base
      MIN_STREAK = 4

      def call
        return [] if over?

        run = streak
        return [] if run.size < MIN_STREAK

        [ result("#{name} has failed to exceed #{line} #{stat_label} in #{run.size} straight games.", 100, run.size) ]
      end
    end
  end
end
