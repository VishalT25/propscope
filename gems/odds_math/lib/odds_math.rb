# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/util"
require_relative "odds_math/version"
require_relative "odds_math/errors"
require_relative "odds_math/conversions"
require_relative "odds_math/devig"
require_relative "odds_math/ev"

# Betting-odds math. All results are BigDecimal (or Integer for American odds).
module OddsMath
  extend Conversions

  # Decimal-odds results are rounded to this many places (matches numeric(8,4)).
  DECIMAL_SCALE = 4
  # Probabilities are rounded to this many places.
  PROB_SCALE = 6
end
