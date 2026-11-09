# frozen_string_literal: true

module OddsMath
  class Error < StandardError; end
  class InvalidOdds < Error; end
  class InvalidProbability < Error; end
end
