module Games
  # Moneyline / spread / total for a game: for each side, the main line (the one most books agree on) and its best price.
  class Lines
    Cell = Data.define(:market, :outcome, :line, :price)
    Result = Data.define(:moneyline, :spread, :total) # each: { "home" => Cell|nil, "away" => ... } or over/under

    TYPES = { "moneyline" => %w[home away], "spread" => %w[home away], "total" => %w[over under] }.freeze

    def self.call(game:, bookmaker_ids: nil)
      markets = game.markets.where(player_id: nil, market_type: TYPES.keys, period: "game", is_alternate: false).to_a
      prices = BestPrice.for(market_ids: markets.map(&:id), bookmaker_ids: bookmaker_ids)
      cells = TYPES.to_h do |type, outcomes|
        sides = outcomes.to_h do |outcome|
          candidates = markets.select { |m| m.market_type == type && prices[[ m.id, outcome ]] }
          best = candidates.max_by { |m| [ prices[[ m.id, outcome ]].books_count, prices[[ m.id, outcome ]].decimal_odds ] }
          [ outcome, best && Cell.new(market: best, outcome: outcome, line: best.line, price: prices[[ best.id, outcome ]]) ]
        end
        [ type, sides ]
      end
      Result.new(**cells.transform_keys(&:to_sym))
    end
  end
end
