module Slips
  # Settles saved legs from the box scores we already store (player game logs). Nothing is guessed:
  #   * a log with minutes: hit, miss or push against the line saved with the leg;
  #   * a log with no minutes (a DNP), or a postponed game: void (the leg drops out of the parlay);
  #   * no log yet: the leg stays pending.
  class Grade
    def self.call(**) = new(**).call

    def initialize(legs: SlipLeg.pending)
      @legs = legs
    end

    # Returns the number of legs that were settled.
    def call
      legs = @legs.includes(market: :game).to_a
      logs = PlayerGameLog.where(game_id: legs.map { |l| l.market.game_id }.uniq, player_id: legs.filter_map { |l| l.market.player_id }.uniq)
                          .index_by { |l| [ l.player_id, l.game_id ] }
      legs.count { |leg| grade(leg, logs[[ leg.market.player_id, leg.market.game_id ]]) }
    end

    private

    def grade(leg, log)
      return settle(leg, "void") if leg.market.game.postponed?
      return false unless log
      return settle(leg, "void") if log.dnp?

      value = StatCatalog.for_market(leg.market.market_type).value(log)
      hit = HitRateCalculator.outcome(value, leg.line, leg.side)
      settle(leg, hit.nil? ? "push" : (hit ? "hit" : "miss"), actual: value)
    end

    def settle(leg, result, actual: nil)
      leg.update!(result: result, actual: actual, graded_at: Time.current)
      true
    end
  end
end
