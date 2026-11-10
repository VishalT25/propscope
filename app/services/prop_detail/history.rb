class PropDetail
  # Past performers of the same position against this opponent (this and last season): result, the line they faced
  # (its closing line when we have one) and whether it cleared.
  class History
    Row = Data.define(:player, :date, :value, :line, :line_kind, :outcome, :odds, :matchup)

    LIMIT = 10
    ALL_LIMIT = 40

    def self.call(market:, opponent:, position:, closing_for:, side: "over", all: false)
      stat = StatCatalog.for_market(market.market_type)
      scope = PlayerGameLog.played.joins(:player).where(opponent_team_id: opponent.id, season: [ market.game.season, market.game.season - 1 ])
      scope = scope.where("split_part(players.position, '-', 1) = ?", position) if position != "all" && position.present?
      logs = scope.includes(:player, :team, :opponent_team).order(game_date: :desc).limit(all ? ALL_LIMIT : LIMIT).to_a
      closing = closing_for.call(player_ids: logs.map(&:player_id).uniq)
      odds = OddsSnapshot.where(is_closing: true, outcome: side).joins(:market)
                         .where(markets: { player_id: logs.map(&:player_id).uniq, game_id: logs.map(&:game_id).uniq, market_type: market.market_type })
                         .pluck("markets.player_id", "markets.game_id", "odds_snapshots.american_odds").each_with_object({}) { |(p, g, o), h| h[[ p, g ]] ||= o }
      logs.map do |log|
        value = stat.value(log)
        line = closing[[ log.player_id, market.market_type, log.game_id ]]
        kind = line ? :closing : :current
        line ||= market.line
        matchup = log.home ? "#{log.opponent_team.abbreviation} @ #{log.team.abbreviation}" : "#{log.team.abbreviation} @ #{log.opponent_team.abbreviation}"
        Row.new(player: log.player, date: log.game_date, value: value, line: line, line_kind: kind, outcome: HitRateCalculator.outcome(value, line, side),
                odds: odds[[ log.player_id, log.game_id ]], matchup: matchup)
      end
    end
  end
end
