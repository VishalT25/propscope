# Box scores for finished games. Nightly 04:00 ET (yesterday's slate by default).
class IngestGameLogsJob < ApplicationJob
  include ProviderAccess
  queue_as :default

  def perform(date = nil)
    provider = provider_for(:stats) or return
    date = date ? Date.parse(date.to_s) : Time.current.in_time_zone(Game::SLATE_ZONE).to_date - 1
    with_budget_handling do
      Ingest::GameLogs.call(logs: provider.fetch_game_logs(sport: "nba", date: date))
    end
  end
end
