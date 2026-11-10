module EvHelper
  def pair_label(pair, side)
    s = pair.side_of(side)
    game = pair.game
    case pair.market_type
    when "moneyline" then "#{(s.outcome == 'home' ? game.home_team : game.away_team).name} moneyline"
    when "spread" then "#{(s.outcome == 'home' ? game.home_team : game.away_team).abbreviation} #{number_with_precision(s.market.line, precision: 1, strip_insignificant_zeros: true).then { |l| s.market.line.positive? ? "+#{l}" : l }}"
    when "total" then "#{s.outcome.capitalize} #{number_with_precision(s.market.line, precision: 1)} total points"
    else "#{pair.player.full_name} #{pick_label(s.outcome, s.market.line, StatCatalog.for_market(pair.market_type))}"
    end
  end

  def pair_path(pair, side)
    s = pair.side_of(side)
    pair.player ? league_prop_path(current_league, s.market, s.outcome) : league_game_path(current_league, pair.game)
  end

  def percent_of(fraction, precision: 1) = "#{number_with_precision(fraction * 100, precision: precision)}%"

  def fair_note(row, books)
    if row.kind == :sharp
      "Fair price: no-vig price at #{books[row.per_book.keys.find { |id| books[id]&.sharp }]&.name || 'the sharp book'}"
    else
      "Fair price: no-vig average of #{row.books_used} books (no sharp book on the free data tier)"
    end
  end
end
