# frozen_string_literal: true

module OddsMath
  # Remove the bookmaker's margin from a set of implied probabilities.
  module Devig
    ITERATIONS = 80
    TOLERANCE = BigDecimal("1e-10")
    WORKING_PRECISION = 16

    module_function

    # Scale every probability by the same factor so the total is 1.
    def multiplicative(probabilities)
      ps = validate!(probabilities)
      total = ps.sum
      ps.map { |p| (p / total).round(PROB_SCALE) }
    end

    # Find k so that sum(p_i ** k) == 1 (Illinois method: bracketed, superlinear, a handful of iterations).
    # Shades longshots more than favourites.
    def power(probabilities)
      ps = validate!(probabilities)
      return ps.map { |p| p.round(PROB_SCALE) } if ps.sum == 1

      lo = BigDecimal("1")
      f_lo = powered_sum(ps, lo) - 1 # > 0 because the probabilities sum to more than 1
      hi = BigDecimal("2")
      f_hi = powered_sum(ps, hi) - 1
      while f_hi.positive? && hi < 1024
        hi *= 2
        f_hi = powered_sum(ps, hi) - 1
      end
      side = 0
      ITERATIONS.times do
        k = (lo * f_hi - hi * f_lo) / (f_hi - f_lo)
        f_k = powered_sum(ps, k) - 1
        break if f_k.abs < TOLERANCE

        if f_k.positive?
          lo, f_lo = k, f_k
          f_hi /= 2 if side == 1 # Illinois: halve the stale end so it cannot stall
          side = 1
        else
          hi, f_hi = k, f_k
          f_lo /= 2 if side == -1
          side = -1
        end
      end
      k = (lo * f_hi - hi * f_lo) / (f_hi - f_lo)
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
