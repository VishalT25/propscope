FactoryBot.define do
  factory :sport do
    key { "nba" }
    name { "NBA" }
    initialize_with { Sport.find_or_create_by!(key: key) { |s| s.name = name } }
  end

  factory :team do
    sport
    sequence(:abbreviation) { |n| "T#{n.to_s.rjust(2, '0')}" }
    sequence(:name) { |n| "City#{n} Testers" }
  end

  factory :player do
    sport
    team
    sequence(:first_name) { |n| "First#{n}" }
    sequence(:last_name) { |n| "Last#{n}" }
    position { "G" }
  end

  factory :game do
    sport
    association :home_team, factory: :team
    association :away_team, factory: :team
    starts_at { 3.hours.from_now }
    season { 2026 }
  end

  factory :bookmaker do
    sequence(:key) { |n| "book#{n}" }
    name { key.titleize }
    code { key.upcase.first(3) }
  end

  factory :market do
    game
    player { association :player, team: game.home_team, sport: game.sport }
    market_type { "player_points" }
    line { 24.5 }
  end

  factory :odds_snapshot do
    market
    bookmaker
    outcome { "over" }
    american_odds { -110 }
    decimal_odds { 1.9091 }
    line { 24.5 }
    captured_at { Time.current }
    source_provider { "sports_game_odds" }
  end

  factory :player_game_log do
    player
    game
    team { player.team }
    opponent_team { game.away_team }
    game_date { Date.current - 1 }
    season { 2026 }
    home { true }
    minutes { 30 }
    points { 20 }
  end
end
