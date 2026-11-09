require "fileutils"

# Records one real slate as fixtures through the live transports. Review before committing:
# provider terms forbid publishing bulk data, so samples must stay small.
class FixtureCapture
  GAMES = 8

  def self.call(root: Rails.root.join("spec/fixtures/providers"), odds: Providers::Registry.for(:odds), stats: Providers::Registry.for(:stats), today: Date.current)
    FileUtils.mkdir_p(root.join("sports_game_odds"))
    FileUtils.mkdir_p(root.join("balldontlie"))
    write(root, "balldontlie/teams", stats.transport.get("/teams"))
    write(root, "balldontlie/players_active", stats.transport.get("/players/active", "per_page" => 100))
    write(root, "balldontlie/games", stats.transport.get("/games", "start_date" => (today - 30).iso8601, "end_date" => (today + 2).iso8601, "per_page" => 100))
    write(root, "sports_game_odds/events", odds.transport.get("/events", "leagueID" => "NBA", "oddsAvailable" => "true", "limit" => GAMES))
  end

  def self.write(root, name, body) = File.write(root.join("#{name}.json"), JSON.pretty_generate(body))
  private_class_method :write
end
