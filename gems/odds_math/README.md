# odds_math

BigDecimal betting-odds math for Ruby: conversions, devigging, EV and Kelly. Plain Ruby, no Rails, **never uses `Float`** for odds or probabilities (Floats are rejected with an error).

```ruby
require "odds_math"

OddsMath.american_to_decimal(-110)        # => 0.19091e1
OddsMath.decimal_to_american("2.5".to_d)  # => 150
OddsMath.american_to_implied(-110)        # => 0.52381e0
OddsMath.implied_to_american("0.6".to_d)  # => -150

# Remove the vig from a two-way market
probs = [-150, 130].map { |a| OddsMath.american_to_implied(a) }
OddsMath::Devig.multiplicative(probs)     # => [0.579832e0, 0.420168e0]
OddsMath::Devig.power(probs)              # shades the longshot more
OddsMath::Devig.overround(probs)          # => 0.034783e0

# Value and sizing
OddsMath::Ev.expected_value(fair_probability: "0.55".to_d, decimal_odds: "2.0".to_d) # => 0.1e0 (+10% per unit)
OddsMath::Ev.kelly(fair_probability: "0.55".to_d, decimal_odds: "2.0".to_d, multiplier: "0.25".to_d)
```

## Arbitrage
```ruby
odds = [BigDecimal("2.10"), BigDecimal("2.05")]
OddsMath::Arbitrage.arbitrage?(odds)               # => true
OddsMath::Arbitrage.profit(odds).round(4)          # => 0.0373 (3.7% guaranteed)
OddsMath::Arbitrage.split(total: "100", decimal_odds: odds)
# => [{stake: 49.40, payout: 103.74}, {stake: 50.60, payout: 103.73}]  (whole cents, stakes sum to the total; payouts match within a cent at typical odds)
```

## Rules
- Decimal odds round to 4 places, probabilities to 6.
- American odds must be an integer with `|odds| >= 100`; otherwise `OddsMath::InvalidOdds`.
- Probabilities must be strictly between 0 and 1; otherwise `OddsMath::InvalidProbability`.
- Accepted inputs: `Integer`, `BigDecimal`, `Rational`, numeric `String`.

## Development
```
bundle install
bundle exec rspec
bundle exec rubocop
gem build odds_math.gemspec
```

MIT licensed.
