# frozen_string_literal: true

require_relative "lib/odds_math/version"

Gem::Specification.new do |spec|
  spec.name = "odds_math"
  spec.version = OddsMath::VERSION
  spec.authors = [ "Propscope contributors" ]
  spec.summary = "BigDecimal betting-odds math: conversions, devigging, EV and Kelly."
  spec.description = "Convert between American, decimal and implied probability, remove vig " \
                     "(multiplicative and power methods), and compute EV and Kelly stakes. " \
                     "Never uses Float for money or probabilities."
  spec.homepage = "https://github.com/OWNER/odds_math"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md"]
  spec.require_paths = [ "lib" ]
  spec.add_dependency "bigdecimal", ">= 3.1"
end
