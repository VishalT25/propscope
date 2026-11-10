# Two-way markets where the best price on each side, across the enabled books, implies under 100% in total:
# back both and one of them always pays.
class ArbitrageFinder
  Row = Data.define(:pair, :left_snap, :right_snap, :profit) do # profit: fraction of the total stake
    def decimals = [ left_snap.decimal_odds, right_snap.decimal_odds ]
    def split(total) = OddsMath::Arbitrage.split(total: total, decimal_odds: decimals)
  end

  def self.call(min_profit: BigDecimal(0), bookmaker_ids: nil, now: Time.current)
    TwoWayMarkets.call(now: now).filter_map do |pair|
      left = best(pair.left_snaps, bookmaker_ids)
      right = best(pair.right_snaps, bookmaker_ids)
      next unless left && right && left.bookmaker_id != right.bookmaker_id # one book pricing both sides never beats its own vig

      decimals = [ left.decimal_odds, right.decimal_odds ]
      next unless OddsMath::Arbitrage.arbitrage?(decimals)

      profit = OddsMath::Arbitrage.profit(decimals)
      Row.new(pair: pair, left_snap: left, right_snap: right, profit: profit) if profit * 100 >= min_profit
    end.sort_by { |r| [ -r.profit, r.pair.key ] }
  end

  def self.best(snaps, bookmaker_ids)
    pool = bookmaker_ids ? snaps.select { |s| bookmaker_ids.include?(s.bookmaker_id) } : snaps
    pool.max_by(&:decimal_odds)
  end
  private_class_method :best
end
