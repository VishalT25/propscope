module Slips
  # The overall result of a saved slip, from its legs' results. Pushed and void legs count as 1.00 (they drop out of the parlay).
  #   lost    any leg missed (decided early, even if other games are still to play)
  #   pending some leg has no result yet
  #   won     everything is settled and at least one leg hit; pays stake x the product of the hit legs' prices
  #   push    everything is settled and nothing hit (all pushed or void); the stake comes back
  class Settlement
    Result = Data.define(:status, :decimal, :payout, :profit)

    def self.call(slip) = new(slip).call

    def initialize(slip)
      @slip = slip
    end

    def call
      legs = @slip.legs.to_a
      results = legs.map(&:result)
      status = if results.include?("miss") then :lost
      elsif results.include?(nil) then :pending
      elsif results.include?("hit") then :won
      else :push
      end
      stake = @slip.stake

      case status
      when :won
        decimal = legs.select { |l| l.result == "hit" }.map(&:decimal_odds).reduce(:*).round(4)
        Result.new(status, decimal, (stake * decimal).round(2), (stake * (decimal - 1)).round(2))
      when :push then Result.new(status, BigDecimal(1), stake, BigDecimal(0))
      when :lost then Result.new(status, nil, BigDecimal(0), -stake)
      else Result.new(status, nil, nil, nil)
      end
    end
  end
end
