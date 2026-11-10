module Insights
  module Rules
    # How the player does at THIS game's venue (home or road).
    class HomeRoadSplit < Base
      MIN_RATE = 80

      def call
        venue_games = c.values.select { |g| g.home == c.home }.first(10)
        hits, n, rate = tally(venue_games)
        return [] if n < MIN_SAMPLE || rate < MIN_RATE

        [ result("#{name} has #{verb} #{line} #{stat_label} in #{hits} of the last #{n} #{c.home ? 'home' : 'road'} games.", rate, n) ]
      end
    end
  end
end
