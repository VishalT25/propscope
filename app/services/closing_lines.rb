# Closing line per (player, market type, game): the line most books closed on, from snapshots flagged is_closing.
class ClosingLines
  # => { [player_id, market_type, game_id] => BigDecimal line }
  def self.call(player_ids:)
    rows = OddsSnapshot.where(is_closing: true).joins(:market).where(markets: { player_id: player_ids })
                       .pluck("markets.player_id", "markets.market_type", "markets.game_id", "markets.line")
    rows.group_by { |p, t, g, _| [ p, t, g ] }.transform_values { |v| v.map(&:last).tally.max_by { |line, count| [ count, -line ] }.first }
  end
end
