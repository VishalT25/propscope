# frozen_string_literal: true

module OddsMath
  # American <-> decimal <-> implied probability.
  module Conversions
    HUNDRED = BigDecimal("100")
    ONE = BigDecimal("1")

    # +150 => 2.5, -200 => 1.5. Raises for 0 or |odds| < 100.
    def american_to_decimal(american)
      a = validate_american!(american)
      d = a.positive? ? ONE + (a / HUNDRED) : ONE + (HUNDRED / a.abs)
      d.round(DECIMAL_SCALE)
    end

    # 2.5 => 150, 1.5 => -200. Decimal must be > 1. Result rounds to nearest integer.
    def decimal_to_american(decimal)
      d = to_bd(decimal, InvalidOdds)
      raise InvalidOdds, "decimal odds must be > 1, got #{decimal}" unless d > ONE

      if d >= BigDecimal("2")
        ((d - ONE) * HUNDRED).round.to_i
      else
        (-HUNDRED / (d - ONE)).round.to_i
      end
    end

    def decimal_to_implied(decimal)
      d = to_bd(decimal, InvalidOdds)
      raise InvalidOdds, "decimal odds must be > 1, got #{decimal}" unless d > ONE

      (ONE / d).round(PROB_SCALE)
    end

    def american_to_implied(american)
      a = validate_american!(american)
      p = a.negative? ? a.abs / (a.abs + HUNDRED) : HUNDRED / (a + HUNDRED)
      p.round(PROB_SCALE)
    end

    # Probability strictly between 0 and 1 => American odds.
    def implied_to_american(probability)
      decimal_to_american(implied_to_decimal(probability))
    end

    def implied_to_decimal(probability)
      p = validate_probability!(probability)
      (ONE / p).round(DECIMAL_SCALE)
    end

    def validate_probability!(probability)
      p = to_bd(probability, InvalidProbability)
      raise InvalidProbability, "probability must be in (0, 1), got #{probability}" unless p.positive? && p < ONE

      p
    end

    # Accept Integer, BigDecimal, Rational, or numeric String. Floats are rejected on purpose.
    def to_bd(value, error_class = InvalidOdds)
      case value
      when BigDecimal then value
      when Integer then BigDecimal(value)
      when Rational then BigDecimal(value, 20)
      when String then BigDecimal(value, exception: false) || raise(error_class, "not a number: #{value.inspect}")
      else raise error_class, "unsupported type #{value.class} (Float is not allowed)"
      end
    end

    private

    def validate_american!(american)
      a = to_bd(american, InvalidOdds)
      raise InvalidOdds, "american odds must be an integer, got #{american}" unless a == a.to_i
      raise InvalidOdds, "american odds must be <= -100 or >= +100, got #{american}" unless a.abs >= HUNDRED

      a
    end
  end
end
