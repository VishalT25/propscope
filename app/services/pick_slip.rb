# The My Picks slip: picks grouped by the book you will place each one at, with price when added vs price now.
class PickSlip
  Line = Data.define(:pick, :market, :player, :game, :stat, :now_odds, :moved)
  Group = Data.define(:bookmaker, :lines)

  def self.call(user:)
    picks = user.picks.includes(:bookmaker, market: [ :game, { player: :team } ]).order(:created_at).to_a
    return [] if picks.empty?

    current = BestPrice.current_snapshots(market_ids: picks.map(&:market_id).uniq).group_by { |s| [ s.market_id, s.bookmaker_id, s.outcome ] }
    picks.group_by(&:bookmaker).map do |book, group|
      lines = group.map do |pick|
        now = current[[ pick.market_id, book.id, pick.side ]]&.first&.american_odds
        m = pick.market
        Line.new(pick: pick, market: m, player: m.player, game: m.game, stat: StatCatalog.for_market(m.market_type), now_odds: now,
                 moved: now.nil? ? nil : (OddsMath.american_to_decimal(now) <=> OddsMath.american_to_decimal(pick.price_at_add)))
      end
      Group.new(bookmaker: book, lines: lines)
    end.sort_by { |g| g.bookmaker.name }
  end
end
