module Ingest
  # Closing line = the last snapshot at or before tip-off, per (market, outcome, book). Idempotent.
  class MarkClosingLines
    LOOKBACK = 48.hours

    def self.call(now: Time.current)
      OddsSnapshot.connection.update(<<~SQL.squish, "MarkClosingLines")
        UPDATE odds_snapshots SET is_closing = TRUE, updated_at = NOW()
        WHERE is_closing = FALSE AND id IN (
          SELECT DISTINCT ON (s.market_id, s.outcome, s.bookmaker_id) s.id
          FROM odds_snapshots s
          JOIN markets m ON m.id = s.market_id
          JOIN games g ON g.id = m.game_id
          WHERE g.starts_at BETWEEN #{OddsSnapshot.connection.quote(now - LOOKBACK)} AND #{OddsSnapshot.connection.quote(now)}
            AND s.captured_at <= g.starts_at
          ORDER BY s.market_id, s.outcome, s.bookmaker_id, s.captured_at DESC
        )
      SQL
    end
  end
end
