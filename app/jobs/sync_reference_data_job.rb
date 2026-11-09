# Teams, players and the upcoming schedule from the canonical provider. Daily 06:00 ET.
class SyncReferenceDataJob < ApplicationJob
  include ProviderAccess
  queue_as :default

  def perform(days_ahead: 7)
    provider = provider_for(:reference) or return
    with_budget_handling do
      sport = Sport.nba
      Ingest::ReferenceData.call(teams: provider.fetch_teams(sport: "nba"), players: provider.fetch_players(sport: "nba"), sport: sport)
      events = provider.fetch_events(sport: "nba", from: Date.current - 1, to: Date.current + days_ahead)
      Ingest::ReferenceData.call(events: events, sport: sport)
    end
  end
end
