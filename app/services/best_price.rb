# Best price per (market, outcome) across the given bookmakers, using each book's CURRENT snapshot.
# Computed per request (not precomputed) because the book selector changes the answer per user.
#
# "Current" matters when a book moves its line (24.5 -> 25.5): the old line is a separate market that keeps that
# book's last snapshot. A snapshot only counts if it is the book's latest for the same player/stat/game across ALL
# lines, so a superseded line never shows a phantom price. (Alternate lines legitimately coexist, so for them the
# line is part of the identity.)
class BestPrice
  Result = Data.define(:american_odds, :decimal_odds, :bookmaker, :captured_at, :books_count)

  CURRENT_SQL = <<~SQL.squish
    SELECT DISTINCT ON (m.game_id, m.player_id, m.market_type, m.period, m.is_alternate, (CASE WHEN m.is_alternate THEN m.line END), s.bookmaker_id, s.outcome)
           s.*
    FROM odds_snapshots s
    JOIN markets m ON m.id = s.market_id
    JOIN (SELECT DISTINCT game_id, player_id, market_type, period FROM markets WHERE id IN (:market_ids)) k
      ON k.game_id = m.game_id AND k.player_id IS NOT DISTINCT FROM m.player_id AND k.market_type = m.market_type AND k.period = m.period
    WHERE 1 = 1 %<book_clause>s
    ORDER BY m.game_id, m.player_id, m.market_type, m.period, m.is_alternate, (CASE WHEN m.is_alternate THEN m.line END), s.bookmaker_id, s.outcome, s.captured_at DESC, s.id DESC
  SQL

  # The current snapshot per (market, book, outcome) for the given markets.
  def self.current_snapshots(market_ids:, bookmaker_ids: nil)
    return [] if market_ids.empty? || bookmaker_ids == []

    book_clause = bookmaker_ids ? "AND s.bookmaker_id IN (:book_ids)" : ""
    sql = format(CURRENT_SQL, book_clause: book_clause)
    OddsSnapshot.find_by_sql([ sql, { market_ids: market_ids, book_ids: bookmaker_ids } ]).select { |s| market_ids.include?(s.market_id) }
  end

  # => { [market_id, "over"] => Result }
  def self.for(market_ids:, bookmaker_ids: nil)
    snaps = current_snapshots(market_ids: market_ids, bookmaker_ids: bookmaker_ids)
    books = Bookmaker.where(id: snaps.map(&:bookmaker_id).uniq).index_by(&:id)
    snaps.group_by { |s| [ s.market_id, s.outcome ] }.transform_values do |group|
      best = group.max_by { |s| [ s.decimal_odds, s.captured_at ] }
      Result.new(american_odds: best.american_odds, decimal_odds: best.decimal_odds, bookmaker: books[best.bookmaker_id],
                 captured_at: best.captured_at, books_count: group.size)
    end
  end
end
