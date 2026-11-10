module Insights
  # One comparable 0-100 score: hit rate (0-100) weighted by the square root of the sample, so 5 of 5 ranks below 12 of 12.
  module Strength
    def self.score(rate, n)
      return BigDecimal("0") if rate.nil? || n.to_i.zero?

      [ (BigDecimal(rate.to_s) / 100) * BigDecimal(n).sqrt(10) * 25, BigDecimal("100") ].min.round(2)
    end
  end
end
