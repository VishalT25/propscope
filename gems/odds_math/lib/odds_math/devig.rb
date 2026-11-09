# frozen_string_literal: true

module OddsMath
  # Remove the bookmaker's margin from a set of implied probabilities.
  module Devig
    ITERATIONS = 200
    WORKING_PRECISION = 30

    module_function

    # Scale every probability by the same factor so the total is 1.
    def multiplicative(probabilities)
      ps = validate!(probabilities)
      total = ps.sum
      ps.map { |p| (p / total).round(PROB_SCALE) }
    end

    # Find k so that sum(p_i ** k) == 1 (bisection). Shades longshots more than favourites.
    def power(probabilities)
      ps = validate!(probabilities)
      return ps.map { |p| p.round(PROB_SCALE) } if ps.sum == 1

      lo = BigDecimal("1")
      hi = BigDecimal("2")
      hi *= 2 while powered_sum(ps, hi) > 1 && hi < 1024
      ITERATIONS.times do
        mid = (lo + hi) / 2
        powered_sum(ps, mid) > 1 ? lo = mid : hi = mid
      end
      k = (lo + hi) / 2
      ps.map { |p| p.power(k, WORKING_PRECISION).round(PROB_SCALE) }
    end

    # Total implied probability minus 1 (the vig / overround).
    def overround(probabilities)
      validate!(probabilities).sum - 1
    end

    def powered_sum(ps, k)
      ps.sum { |p| p.power(k, WORKING_PRECISION) }
    end

    def validate!(probabilities)
      raise InvalidProbability, "need at least 2 outcomes" unless probabilities.respond_to?(:size) && probabilities.size >= 2

      probabilities.map { |p| OddsMath.validate_probability!(p) }
    end
    private_class_method :powered_sum, :validate!
  end
end
