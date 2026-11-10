class PropDetail
  # How the market has moved: replays every snapshot for this player/stat/game/side in time order, keeping the latest
  # line and price per book, and records a point whenever the consensus (median) line or the best price changes.
  class LineMovement
    Point = Data.define(:at, :line, :best_odds, :books, :line_change, :odds_change, :line_delta)
    Result = Data.define(:points)

    def self.call(**) = new(**).call

    def initialize(market:, side:, bookmaker_ids: nil)
      @market, @side, @bookmaker_ids = market, side, bookmaker_ids
    end

    def call
      snaps = OddsSnapshot.joins(:market)
                          .where(markets: { game_id: @market.game_id, player_id: @market.player_id, market_type: @market.market_type }, outcome: @side)
                          .then { |s| @bookmaker_ids ? s.where(bookmaker_id: @bookmaker_ids) : s }
                          .order(:captured_at, :id).to_a
      state = {}
      points = []
      snaps.each do |snap|
        state[snap.bookmaker_id] = snap
        line = median(state.values.map { |s| s.line.to_d })
        best = state.values.max_by(&:decimal_odds).american_odds
        prev = points.last
        next if prev && prev.line == line && prev.best_odds == best

        points << Point.new(at: snap.captured_at, line: line, best_odds: best, books: state.size,
                            line_change: prev && (line <=> prev.line), odds_change: prev && (best <=> prev.best_odds), line_delta: prev && (line - prev.line))
      end
      Result.new(points: points)
    end

    private

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    end
  end
end
