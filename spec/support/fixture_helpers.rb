module FixtureHelpers
  # A tiny canonical world: 2 teams, 2 players, 1 game. External IDs registered for the "balldontlie" provider.
  def build_world
    sport = create(:sport)
    home = create(:team, sport: sport, abbreviation: "BOS", name: "Boston Celtics")
    away = create(:team, sport: sport, abbreviation: "LAL", name: "Los Angeles Lakers")
    game = create(:game, sport: sport, home_team: home, away_team: away, starts_at: Time.utc(2026, 11, 10, 0, 0))
    p1 = create(:player, sport: sport, team: home, first_name: "Dušan", last_name: "Marković")
    p2 = create(:player, sport: sport, team: away, first_name: "Jaylen", last_name: "Brooks Jr.")
    { sport:, home:, away:, game:, p1:, p2: }
  end

  def quote(**over)
    base = Dto::TeamRef.new(external_id: "BOSTON_CELTICS_NBA", name: "Boston Celtics", abbreviation: "BOS")
    away = Dto::TeamRef.new(external_id: "LOS_ANGELES_LAKERS_NBA", name: "Los Angeles Lakers", abbreviation: "LAL")
    Dto::OddsQuote.new(**{
      provider: "sports_game_odds", event_id: "EVT1", home_team: base, away_team: away, starts_at: Time.utc(2026, 11, 10, 0, 0),
      bookmaker_key: "draftkings", market_type: "moneyline", period: "game", player: nil, line: nil, outcome: "home",
      american_odds: -150, captured_at: Time.utc(2026, 11, 9, 15, 0), is_alternate: false
    }.merge(over))
  end
end

RSpec.configure { |c| c.include FixtureHelpers }
