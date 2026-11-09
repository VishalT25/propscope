# Best price per (market, outcome) across the given bookmakers, using each book's LATEST snapshot.
# Computed per request (not precomputed) because the book selector changes the answer per user.
class BestPrice
  Result = Data.define(:american_odds, :decimal_odds, :bookmaker, :captured_at, :books_count)

  # => { [market_id, "over"] => Result }
  def self.for(market_ids:, bookmaker_ids: nil)
    return {} if market_ids.empty? || bookmaker_ids == []

    book_clause = bookmaker_ids ? "AND bookmaker_id IN (:book_ids)" : ""
    sql = <<~SQL.squish
      SELECT DISTINCT ON (s.market_id, s.outcome) s.*, COUNT(*) OVER (PARTITION BY s.market_id, s.outcome) AS books_count
      FROM (
        SELECT DISTINCT ON (market_id, outcome, bookmaker_id) *
        FROM odds_snapshots
        WHERE market_id IN (:market_ids) #{book_clause}
        ORDER BY market_id, outcome, bookmaker_id, captured_at DESC
      ) s
      ORDER BY s.market_id, s.outcome, s.decimal_odds DESC, s.captured_at DESC
    SQL
    snaps = OddsSnapshot.find_by_sql([ sql, { market_ids: market_ids, book_ids: bookmaker_ids } ])
    books = Bookmaker.where(id: snaps.map(&:bookmaker_id).uniq).index_by(&:id)
    snaps.to_h do |s|
      [ [ s.market_id, s.outcome ], Result.new(american_odds: s.american_odds, decimal_odds: s.decimal_odds, bookmaker: books[s.bookmaker_id],
                                               captured_at: s.captured_at, books_count: s.attributes["books_count"]) ]
    end
  end
end
