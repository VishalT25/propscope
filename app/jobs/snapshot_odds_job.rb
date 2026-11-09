# Odds snapshots for games in the next 36h.
#   morning / afternoon : whole window (optional: dropped at 80% of budget)
#   tick                : every 10 min; fetches only games near T-90 (optional), T-20 or tip (both required)
class SnapshotOddsJob < ApplicationJob
  include ProviderAccess
  queue_as :default

  PROVIDER = "sports_game_odds".freeze
  HORIZON = 36.hours
  # [range in whole minutes before tip, optional?]
  TICK_WINDOWS = [ [ 85...95, true ], [ 15...25, false ], [ -5...5, false ] ].freeze

  def perform(slot = "morning")
    provider = provider_for(:odds) or return
    now = Time.current
    games = slot == "tick" ? tick_games(now) : Game.upcoming(within: HORIZON, now: now).to_a
    return if games.empty?

    if games.all? { |g| optional?(g, slot, now) } && !BudgetGuard.optional_allowed?(PROVIDER, now: now)
      Rails.logger.info("[SnapshotOddsJob] optional #{slot} snapshot dropped: budget ceiling reached")
      return
    end

    with_budget_handling do
      Ingest::OddsSnapshots.call(quotes: fetch(provider, games, now))
      PrecomputeHitRatesJob.perform_later
    end
  end

  private

  def fetch(provider, games, now)
    ids = games.map { |g| ExternalId.where(provider: PROVIDER, external_type: "game", internal_type: "Game", internal_id: g.id).pick(:external_id) }
    if ids.all?(&:present?)
      provider.fetch_odds(sport: "nba", event_ids: ids)
    else
      provider.fetch_odds(sport: "nba", from: [ games.map(&:starts_at).min - 1.minute, now ].min, to: games.map(&:starts_at).max + 1.minute)
    end
  end

  def tick_games(now) = Game.upcoming(within: HORIZON, now: now - 5.minutes).select { |g| tick_window(g, now) }

  def tick_window(game, now) = TICK_WINDOWS.find { |range, _| range.cover?(((game.starts_at - now) / 60).floor) }

  def optional?(game, slot, now) = slot != "tick" || tick_window(game, now)&.last
end
