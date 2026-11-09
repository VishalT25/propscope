module Ingest
  # Fills a fresh database from the recorded fixtures: zero API keys, zero budget.
  class SeedFixtures
    def self.call(today: Date.current)
      provider = Providers::Fixture.new(today: today)
      sport = Sport.nba

      Ingest::ReferenceData.call(teams: provider.fetch_teams(sport: "nba"), players: provider.fetch_players(sport: "nba"), sport: sport)
      events = provider.fetch_events(sport: "nba", from: today - 45, to: today + 3)
      Ingest::ReferenceData.call(events: events, sport: sport)

      (today - 45..today - 1).each do |date|
        Ingest::GameLogs.call(logs: provider.fetch_game_logs(sport: "nba", date: date))
      end
      Ingest::OddsSnapshots.call(quotes: provider.fetch_odds(sport: "nba", from: Time.current, to: Time.current + 36.hours), sport: sport)
      DefenseRanker.call(season: Game.maximum(:season))
      HitRates::Precompute.call
    end
  end
end
