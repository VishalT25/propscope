module Ingest
  # Fills a fresh database from the recorded fixtures: zero API keys, zero budget.
  class SeedFixtures
    # Fixtures hold one price per book, so line movement would be empty. Replay two EARLIER, deterministically perturbed
    # snapshots (oldest first; the ingest ignores anything older than what it already has). Synthetic, dev/demo only.
    HISTORY = [ 9.hours, 4.hours ].freeze

    def self.seed_history(quotes, sport)
      HISTORY.each_with_index do |ago, step|
        older = quotes.filter_map do |q|
          roll = Zlib.crc32([ q.event_id, q.bookmaker_key, q.market_type, q.player&.external_id, q.outcome, step ].join("|"))
          moved = roll % 3 == 0 # about a third of prices have moved since
          next q.with(captured_at: q.captured_at - ago) unless moved

          prob = OddsMath.american_to_implied(q.american_odds) + (BigDecimal((roll % 7) - 3) / 100)
          price = OddsMath.implied_to_american(prob.clamp(BigDecimal("0.08"), BigDecimal("0.92")))
          line = q.line && q.player && roll % 4 == 0 ? q.line - BigDecimal("0.5") : q.line
          q.with(captured_at: q.captured_at - ago, american_odds: price, line: line)
        end
        Ingest::OddsSnapshots.call(quotes: older, sport: sport)
      end
    end

    # Past games in the fixtures have no odds, so "hit rate vs closing line" would be empty. Give the slate's props
    # players a synthetic closing line for each past game (their trailing average, rounded to a .5), flagged is_closing.
    def self.seed_closing_history(now: Time.current)
      return if OddsSnapshot.exists?(source_provider: "fixture_history")

      markets = Market.joins(:game).where(games: { starts_at: now.. }).where.not(player_id: nil).distinct.pluck(:player_id, :market_type)
      book = Bookmaker.for_key("draftkings")
      pairs = markets.flat_map do |player_id, type|
        stat = StatCatalog.for_market(type)
        logs = PlayerGameLog.played.where(player_id: player_id).includes(:game).order(:game_date).to_a
        logs.each_with_index.filter_map do |log, i|
          prior = logs.first(i).last(10).map { |l| stat.value(l) }
          next if prior.size < 3

          line = ((BigDecimal(prior.sum) / prior.size * 2).round / 2) - BigDecimal("0.5") + (i.odd? ? 1 : 0)
          [ { game_id: log.game_id, player_id: player_id, market_type: type, period: "game", line: [ line, BigDecimal("0.5") ].max, is_alternate: false }, log.game.starts_at ]
        end
      end
      return if pairs.empty?

      Market.insert_all(pairs.map(&:first), unique_by: :index_markets_on_natural_key)
      ids = Market.where(game_id: pairs.map { |m, _| m[:game_id] }.uniq, player_id: pairs.map { |m, _| m[:player_id] }.uniq).index_by { |m| [ m.game_id, m.player_id, m.market_type, m.line ] }
      rows = pairs.flat_map do |m, starts_at|
        market = ids.fetch([ m[:game_id], m[:player_id], m[:market_type], m[:line] ])
        %w[over under].map do |outcome|
          { market_id: market.id, bookmaker_id: book.id, outcome: outcome, american_odds: -110, decimal_odds: OddsMath.american_to_decimal(-110),
            line: m[:line], captured_at: starts_at - 10.minutes, source_provider: "fixture_history", is_closing: true }
        end
      end
      OddsSnapshot.insert_all(rows)
    end

    def self.call(today: Date.current)
      provider = Providers::Fixture.new(today: today)
      sport = Sport.nba

      Ingest::ReferenceData.call(teams: provider.fetch_teams(sport: "nba"), players: provider.fetch_players(sport: "nba"), sport: sport)
      events = provider.fetch_events(sport: "nba", from: today - 45, to: today + 3)
      Ingest::ReferenceData.call(events: events, sport: sport)

      (today - 45..today - 1).each do |date|
        Ingest::GameLogs.call(logs: provider.fetch_game_logs(sport: "nba", date: date))
      end
      quotes = provider.fetch_odds(sport: "nba", from: Time.current, to: Time.current + 36.hours)
      seed_history(quotes, sport)
      Ingest::OddsSnapshots.call(quotes: quotes, sport: sport)
      seed_closing_history
      DefenseRanker.call(season: Game.maximum(:season))
      HitRates::Precompute.call
      Insights::Engine.call
    end
  end
end
