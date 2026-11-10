# Builds two-sided markets with prices from several books, for EV and arbitrage specs.
module TwoWayHelpers
  def books(n = 5) = Array.new(n) { |i| create(:bookmaker, key: "book#{i}-#{SecureRandom.hex(2)}", code: "B#{i}") }

  def game_for_two_way = @game_for_two_way ||= create(:game, starts_at: 5.hours.from_now)

  # prices: { book => [over_american, under_american] }
  def prop_with_prices(prices, line: 24.5, game: game_for_two_way, type: "player_points")
    player = create(:player, sport: game.sport, team: game.home_team)
    market = create(:market, game: game, player: player, market_type: type, line: line)
    post_prices(market, prices)
    market
  end

  def post_prices(market, prices, at: Time.current)
    prices.each do |book, (over, under)|
      { "over" => over, "under" => under }.each do |outcome, odds|
        next unless odds

        create(:odds_snapshot, market: market, bookmaker: book, outcome: outcome, american_odds: odds, decimal_odds: OddsMath.american_to_decimal(odds), line: market.line, captured_at: at)
      end
    end
  end
end

RSpec.configure { |c| c.include TwoWayHelpers }
