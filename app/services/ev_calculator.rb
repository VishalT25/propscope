# Expected value and Kelly stake for one price against a fair probability. Thin wrapper over the odds_math gem.
class EvCalculator
  Result = Data.define(:ev, :kelly) # ev: fraction of stake (0.04 = +4%); kelly: fraction of bankroll to stake

  def self.call(fair_probability:, decimal_odds:, kelly_multiplier: BigDecimal("0.25"))
    Result.new(
      ev: OddsMath::Ev.expected_value(fair_probability: fair_probability, decimal_odds: decimal_odds),
      kelly: OddsMath::Ev.kelly(fair_probability: fair_probability, decimal_odds: decimal_odds, multiplier: kelly_multiplier)
    )
  end
end
