module Backfill
  # Loads history from the live providers for a BackfillRun, in phases:
  #   reference   teams, players and the schedule
  #   box_scores  one request group per past game day in the chosen seasons (days already loaded are skipped, so it is resumable)
  #   ranks       defence ranks, hit rates and insights, from our own data
  #   odds        today's odds, so the explorer has something to show
  # Progress is saved on the run as it goes. It stops cleanly (never raises) when the user cancels, when a provider's monthly budget
  # runs out (paused), or on an error (failed, with a message to show), and the run can then be started again.
  class Run
    Stopped = Class.new(StandardError)

    def self.call(run, **) = new(run, **).call

    def initialize(run, provider: nil, log: ->(_message) { })
      @run = run
      @provider = provider
      @log = log
    end

    def call
      @run.beat!(state: "running", started_at: @run.started_at || Time.current, message: nil, cancel_requested: false)
      sync_reference
      load_box_scores
      compute
      fetch_odds
      finish("done")
    rescue Stopped
      @run
    rescue BudgetGuard::BudgetExceeded => e
      finish("paused", "#{e.message}. Start it again next month, or when your plan allows more.")
    rescue Faraday::UnauthorizedError, Faraday::ForbiddenError => e
      finish("failed", "The provider turned the request down (HTTP #{e.response_status}). Check the key in Settings. Box scores need BallDontLie's paid plan.")
    rescue ApiKeys::Missing => e
      finish("failed", e.message)
    rescue StandardError => e
      Rails.logger.error("[Backfill] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
      finish("failed", "Something went wrong (#{e.class}: #{e.message}). Whatever was loaded is kept; start it again to carry on.")
    end

    private

    def provider = @provider ||= Providers::Registry.for(:stats)

    def sport = @sport ||= Sport.nba

    def seasons_range
      today = Date.current
      current = today.month >= 10 ? today.year : today.year - 1
      [ Date.new(current - @run.seasons + 1, 10, 1), today - 1 ]
    end

    def sync_reference
      phase("reference", "Loading teams, players and the schedule")
      start, = seasons_range
      Ingest::ReferenceData.call(teams: provider.fetch_teams(sport: "nba"), players: provider.fetch_players(sport: "nba"), sport: sport)
      Ingest::ReferenceData.call(events: provider.fetch_events(sport: "nba", from: start, to: Date.current + 7), sport: sport)
    end

    def load_box_scores
      phase("box_scores", "Loading box scores")
      start, finish = seasons_range
      days = Game.where(slate_date: start..finish).distinct.order(:slate_date).pluck(:slate_date)
      todo = days.reject { |d| PlayerGameLog.exists?(game_date: d) }
      @run.beat!(total_days: todo.size, done_days: 0)
      @log.call("#{days.size} game days, #{todo.size} still to load")

      todo.each_with_index do |date, i|
        stop_if_cancelled
        result = Ingest::GameLogs.call(logs: provider.fetch_game_logs(sport: "nba", date: date))
        @run.beat!(done_days: i + 1)
        @log.call("[#{i + 1}/#{todo.size}] #{date}: #{result.upserted} logs (#{result.skipped} skipped)") if (i % 10).zero? || i == todo.size - 1
      end
    end

    def compute
      stop_if_cancelled
      phase("ranks", "Working out defence ranks, hit rates and insights")
      season = Game.where("starts_at >= ?", Time.current).order(:starts_at).pick(:season) || Game.maximum(:season)
      DefenseRanker.call(season: season) if season
      HitRates::Precompute.call
      Insights::Engine.call
    end

    def fetch_odds
      stop_if_cancelled
      phase("odds", "Fetching today's odds")
      SnapshotOddsJob.perform_now("morning")
      HitRates::Precompute.call
    end

    def phase(name, message)
      @run.beat!(phase: name)
      @log.call(message)
    end

    def stop_if_cancelled
      return unless @run.reload.cancel_requested?

      finish("cancelled", "Stopped. What was loaded is kept; start it again to carry on.")
      raise Stopped
    end

    def finish(state, message = nil)
      @run.update!(state: state, message: message, finished_at: Time.current, heartbeat_at: Time.current)
      @run
    end
  end
end
