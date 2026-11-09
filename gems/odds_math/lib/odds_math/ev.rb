# frozen_string_literal: true

module OddsMath
  # Expected value and Kelly sizing. Stakes are in units of bankroll (1 == whole bankroll).
  module Ev
    module_function

    # Expected profit per 1 unit staked. Positive means +EV.
    def expected_value(fair_probability:, decimal_odds:)
      p = OddsMath.validate_probability!(fair_probability)
      d = OddsMath.to_bd(decimal_odds, InvalidOdds)
      raise InvalidOdds, "decimal odds must be > 1, got #{decimal_odds}" unless d > 1

      (p * d - 1).round(PROB_SCALE)
    end

    # Kelly fraction of bankroll to stake, scaled by `multiplier` (0.25 = quarter Kelly).
    # Returns 0 when there is no edge. Never negative.
    def kelly(fair_probability:, decimal_odds:, multiplier: BigDecimal("1"))
      ev = expected_value(fair_probability:, decimal_odds:)
      return BigDecimal("0") unless ev.positive?

      m = OddsMath.to_bd(multiplier, Error)
      raise Error, "multiplier must be in (0, 1]" unless m.positive? && m <= 1

      (ev / (OddsMath.to_bd(decimal_odds, InvalidOdds) - 1) * m).round(PROB_SCALE)
    end
  end
end
