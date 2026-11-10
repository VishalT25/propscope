# frozen_string_literal: true

module OddsMath
  # Two-way (or n-way) arbitrage: back every outcome so the payout is the same whichever one wins.
  module Arbitrage
    module_function

    # Sum of the implied probabilities of the best prices. Below 1 means a guaranteed profit exists.
    def total_implied(decimal_odds)
      validate!(decimal_odds)
      decimal_odds.sum { |d| BigDecimal(1) / BigDecimal(d.to_s) }
    end

    # Guaranteed profit as a fraction of the total stake (0.03 = 3%). Negative when there is no arbitrage.
    def profit(decimal_odds) = (BigDecimal(1) / total_implied(decimal_odds)) - 1

    def arbitrage?(decimal_odds) = total_implied(decimal_odds) < 1

    # Splits `total` (dollars) into whole-cent stakes so each outcome returns (almost) the same amount.
    # Stakes always sum to exactly `total`. Returns [{ stake:, payout: }] in the order of `decimal_odds`.
    def split(total:, decimal_odds:)
      validate!(decimal_odds)
      cents = (BigDecimal(total.to_s) * 100).round.to_i
      raise InvalidOdds, "total stake must be positive" unless cents.positive?

      implied = decimal_odds.map { |d| BigDecimal(1) / BigDecimal(d.to_s) }
      sum = implied.sum
      stakes = implied.map { |i| (BigDecimal(cents) * i / sum).round.to_i }
      stakes[stakes.each_with_index.max_by { |s, _| s }.last] += cents - stakes.sum # put the rounding remainder on the biggest stake
      stakes = closest_two_way(cents, decimal_odds, stakes) if stakes.size == 2
      stakes.each_with_index.map do |stake, i|
        { stake: BigDecimal(stake) / 100, payout: (BigDecimal(stake) * BigDecimal(decimal_odds[i].to_s) / 100).round(2) }
      end
    end

    # With whole-cent stakes the payouts cannot always match exactly (one cent of stake moves the payouts by about
    # the decimal odds in cents), so try the few cent splits around the ideal one and keep the closest pair.
    def closest_two_way(cents, decimal_odds, stakes)
      odds = decimal_odds.map { |d| BigDecimal(d.to_s) }
      candidates = (-3..3).map { |delta| [ stakes[0] + delta, cents - stakes[0] - delta ] }.select { |a, b| a.positive? && b.positive? }
      candidates.min_by do |a, b|
        pay = [ a * odds[0], b * odds[1] ]
        [ (pay[0] - pay[1]).abs.round(0), -pay.min ]
      end
    end

    def validate!(decimal_odds)
      raise InvalidOdds, "need at least 2 outcomes" unless decimal_odds.respond_to?(:size) && decimal_odds.size >= 2

      decimal_odds.each do |d|
        v = OddsMath.to_bd(d, InvalidOdds)
        raise InvalidOdds, "decimal odds must be > 1, got #{d}" unless v > 1
      end
    end
  end
end
