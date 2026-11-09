class PropDetail
  # Past performers of the same position against this opponent (this and last season): result, the line they faced
  # (its closing line when we have one) and whether it cleared.
  class History
    Row = Data.define(:player, :date, :value, :line, :line_kind, :outcome)

    LIMIT = 20

    def self.call(market:, opponent:, position:, closing_for:)
      stat = StatCatalog.for_market(market.market_type)
      scope = PlayerGameLog.played.joins(:player).where(opponent_team_id: opponent.id, season: [ market.game.season, market.game.season - 1 ])
      scope = scope.where("split_part(players.position, '-', 1) = ?", position) if position != "all" && position.present?
      logs = scope.includes(:player).order(game_date: :desc).limit(LIMIT).to_a
      closing = closing_for.call(player_ids: logs.map(&:player_id).uniq)
      logs.map do |log|
        value = stat.value(log)
        line = closing[[ log.player_id, market.market_type, log.game_id ]]
        kind = line ? :closing : :current
        line ||= market.line
        Row.new(player: log.player, date: log.game_date, value: value, line: line, line_kind: kind, outcome: HitRateCalculator.outcome(value, line, "over"))
      end
    end
  end
end
