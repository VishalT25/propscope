module Insights
  module Rules
    # "As favourite / underdog", approximated by record: games where the player's team had the better (or worse) win % than
    # the opponent going in, matching tonight. We do not store historical odds, so this says "better record", not "favourite".
    class RecordEdge < Base
      MIN_RATE = 80

      def call
        better = c.better_record
        return [] if better.nil?

        same = c.values.select { |g| c.records_edge.call(g) == better }
        hits, n, rate = tally(same)
        return [] if n < MIN_SAMPLE || rate < MIN_RATE

        [ result("#{name} has #{verb} #{line} #{stat_label} in #{hits} of #{n} games when the team had the #{better ? 'better' : 'worse'} record.", rate, n) ]
      end
    end
  end
end
