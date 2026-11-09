module Providers
  # Dev/test provider: the real adapters' parsers fed by recorded JSON instead of HTTP.
  class Fixture
    attr_reader :odds, :stats

    def initialize(today: Date.current, clock: -> { Time.current })
      @odds = SportsGameOdds.new(transport: FixtureTransport.new("sports_game_odds", today: today), clock: clock)
      @stats = BallDontLie.new(transport: FixtureTransport.new("balldontlie", today: today), clock: clock)
    end

    def provider_key = "fixture"
    def live? = false
    def capabilities = Set[:odds, :props, :stats]

    def fetch_teams(**kw) = stats.fetch_teams(**kw)
    def fetch_players(**kw) = stats.fetch_players(**kw)
    def fetch_events(**kw) = stats.fetch_events(**kw)
    def fetch_game_logs(**kw) = stats.fetch_game_logs(**kw)
    def fetch_odds(**kw) = odds.fetch_odds(**kw)
    def cost_of(*) = 0
  end
end
