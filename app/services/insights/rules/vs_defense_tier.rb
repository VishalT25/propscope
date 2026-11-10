module Insights
  module Rules
    # Results against defences in the same tier as tonight's opponent (bottom-third = weakest, top-third = toughest).
    class VsDefenseTier < Base
      MIN_RATE = 75

      def call
        tier = c.opponent_tier
        return [] unless %w[favorable unfavorable].include?(tier) # raw tier: favorable = weak defence for scoring

        same = c.values.select { |g| c.ranks[g.opponent_id]&.tier == tier }
        hits, n, rate = tally(same)
        return [] if n < MIN_SAMPLE - 1 || rate < MIN_RATE

        label = tier == "favorable" ? "bottom-third defenses" : "top-third defenses"
        [ result("#{name} has #{verb} #{line} #{stat_label} in #{hits} of #{n} games against #{label}.", rate, n) ]
      end
    end
  end
end
