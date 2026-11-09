module HitRates
  # Fills prop_hit_rates for every player prop on games that have not started, both sides.
  # Pages read this table; nothing is calculated on request.
  class Precompute
    SIDES = %w[over under].freeze

    def self.call(**) = new(**).call

    def initialize(now: Time.current)
      @now = now
    end

    def call
      markets = Market.joins(:game).where(games: { starts_at: @now.. }).where.not(player_id: nil)
                      .where(market_type: StatCatalog::BY_MARKET.keys).includes(:game, :player).to_a
      return 0 if markets.empty?

      logs = PlayerGameLog.played.where(player_id: markets.map(&:player_id).uniq).to_a.group_by(&:player_id)
      closing = ClosingLines.call(player_ids: markets.map(&:player_id).uniq)
      rows = markets.flat_map { |market| SIDES.filter_map { |side| row_for(market, side, logs[market.player_id] || [], closing) } }
      PropHitRate.upsert_all(rows, unique_by: %i[market_id side]) if rows.any?
      rows.size
    end

    private

    def row_for(market, side, player_logs, closing)
      game = market.game
      team_id = market.player.team_id
      return nil unless team_id && [ game.home_team_id, game.away_team_id ].include?(team_id)

      stat = StatCatalog.for_market(market.market_type)
      values = HitRateCalculator.game_values(player_logs, stat)
      opponent = game.home_team_id == team_id ? game.away_team_id : game.home_team_id
      result = HitRateCalculator.call(games: values, line: market.line, side: side, opponent_id: opponent, current_season: game.season)
      w = result.windows

      { market_id: market.id, side: side, line: market.line,
        l5: w[:l5].rate, l10: w[:l10].rate, l20: w[:l20].rate, h2h: w[:h2h].rate, season: w[:season].rate, prev_season: w[:prev_season].rate,
        l5_n: w[:l5].n, l10_n: w[:l10].n, l20_n: w[:l20].n, h2h_n: w[:h2h].n, season_n: w[:season].n, prev_season_n: w[:prev_season].n,
        closing_line_hit_rate: closing_rate(values, market, side, closing),
        mean: result.mean, median: result.median, computed_at: @now }
    end

    # Hit rate vs each past game's CLOSING line (L10 played games that have a closing line on file).
    def closing_rate(values, market, side, closing)
      # NB: map + compact, not filter_map: a miss is `false` and must be kept. nil = push or no closing line on file.
      outcomes = HitRateCalculator.played(values).first(10).map do |gv|
        line = closing[[ market.player_id, market.market_type, gv.game_id ]]
        line && HitRateCalculator.outcome(gv.value, line, side)
      end.compact
      outcomes.empty? ? nil : (BigDecimal(outcomes.count(true)) * 100 / outcomes.size).round(2)
    end
  end
end
