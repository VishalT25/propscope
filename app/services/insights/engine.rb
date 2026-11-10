module Insights
  Result = Data.define(:rule_key, :statement, :strength)

  Context = Data.define(:market, :side, :player, :game, :stat, :values, :home, :opponent_tier, :ranks, :better_record, :records_edge)

  # Runs every rule over every upcoming player prop (both sides) and stores the strongest results.
  # Idempotent: each run replaces the insights of the games it covers.
  class Engine
    RULES = [ Rules::HitStreak, Rules::MissStreak, Rules::HomeRoadSplit, Rules::VsDefenseTier, Rules::RecordEdge ].freeze
    MIN_STRENGTH = 40

    def self.call(**) = new(**).call

    def initialize(now: Time.current)
      @now = now
    end

    def call
      markets = Market.joins(:game).where(games: { starts_at: @now.. }).where.not(player_id: nil).where(is_alternate: false)
                      .where(market_type: StatCatalog::BY_MARKET.keys).includes(:game, player: :team).to_a
      games = markets.map(&:game).uniq
      return 0 if games.empty?

      priced = BestPrice.for(market_ids: markets.map(&:id)).keys.to_set
      logs = PlayerGameLog.played.where(player_id: markets.map(&:player_id).uniq).to_a.group_by(&:player_id)
      records = TeamRecords.call(season: games.first.season)
      ranks = DefenseRank.where(season: games.first.season).group_by { |r| [ r.stat, r.position ] }.transform_values { |v| v.index_by(&:team_id) }

      rows = markets.flat_map do |m|
        %w[over under].select { |side| priced.include?([ m.id, side ]) }.flat_map { |side| rows_for(m, side, logs[m.player_id] || [], records, ranks) }
      end
      Insight.transaction do
        Insight.where(game_id: games.map(&:id)).delete_all
        Insight.insert_all(rows) if rows.any?
      end
      rows.size
    end

    private

    def rows_for(market, side, player_logs, records, ranks)
      ctx = context(market, side, player_logs, records, ranks) or return []
      RULES.flat_map { |rule| rule.call(ctx) }.select { |r| r.strength >= MIN_STRENGTH }.map do |r|
        { subject_type: "Player", subject_id: market.player_id, game_id: market.game_id, market_id: market.id, side: side, rule_key: r.rule_key,
          statement: r.statement, strength: r.strength, computed_at: @now, created_at: @now, updated_at: @now }
      end
    end

    def context(market, side, player_logs, records, ranks)
      game, player = market.game, market.player
      team_id = player.team_id
      return nil unless team_id && [ game.home_team_id, game.away_team_id ].include?(team_id)

      stat = StatCatalog.for_market(market.market_type)
      opponent_id = game.home_team_id == team_id ? game.away_team_id : game.home_team_id
      values = HitRateCalculator.played(HitRateCalculator.game_values(player_logs, stat))
      team_ranks = ranks[[ stat.defense_stat, "all" ]] || {} # overall (team-level) rank, consistent with the explorer
      pct = ->(tid, date) { records.pct_before(tid, date) }
      edge = lambda do |gv|
        mine = pct.call(team_id, gv.date)
        theirs = pct.call(gv.opponent_id, gv.date)
        mine && theirs && mine != theirs ? mine > theirs : nil
      end
      tonight_mine = pct.call(team_id, game.slate_date)
      tonight_theirs = pct.call(opponent_id, game.slate_date)
      better = tonight_mine && tonight_theirs && tonight_mine != tonight_theirs ? tonight_mine > tonight_theirs : nil
      Context.new(market: market, side: side, player: player, game: game, stat: stat, values: values, home: game.home_team_id == team_id,
                  opponent_tier: team_ranks[opponent_id]&.tier, ranks: team_ranks, better_record: better, records_edge: edge)
    end
  end
end
