module Insights
  module Rules
    # "X has gone over 24.5 points in 6 straight games." Over side only.
    class HitStreak < Base
      MIN_STREAK = 4

      def call
        return [] unless over?

        run = streak
        return [] if run.size < MIN_STREAK

        [ result("#{name} has exceeded #{line} #{stat_label} in #{run.size} straight games (#{avg(run)} average).", 100, run.size) ]
      end

      private

      def avg(run) = ActionController::Base.helpers.number_with_precision(run.sum { |g| g.value.to_d } / run.size, precision: 1)
    end
  end
end
