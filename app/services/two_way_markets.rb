# Finds every two-sided market on upcoming games and the CURRENT book prices on each side. EV and arbitrage both start here.
#   props and totals : over / under of one market
#   moneyline        : home / away of one market
#   spread           : the home market at line L paired with the away market at -L
class TwoWayMarkets
  Side = Data.define(:market, :outcome)
  Pair = Data.define(:key, :game, :player, :market_type, :left, :right, :left_snaps, :right_snaps) do
    def line = left.market.line
    def snaps_for(side) = side == :left ? left_snaps : right_snaps
    def side_of(name) = name == :left ? left : right
  end

  MARKET_TYPES = (Market::GAME_TYPES + Market::PLAYER_TYPES).freeze

  def self.call(**) = new(**).call

  def initialize(now: Time.current)
    @now = now
  end

  def call
    markets = Market.joins(:game).where(games: { starts_at: @now.. }, period: "game", is_alternate: false, market_type: MARKET_TYPES)
                    .includes(:game, player: :team).to_a
    snaps = BestPrice.current_snapshots(market_ids: markets.map(&:id)).group_by { |s| [ s.market_id, s.outcome ] }
    pairs(markets).filter_map do |key, game, player, type, left, right|
      l = snaps[[ left.market.id, left.outcome ]]
      r = snaps[[ right.market.id, right.outcome ]]
      Pair.new(key: key, game: game, player: player, market_type: type, left: left, right: right, left_snaps: l, right_snaps: r) if l.present? && r.present?
    end
  end

  private

  def pairs(markets)
    out = []
    markets.group_by(&:market_type).each do |type, ms|
      case type
      when "moneyline" then ms.each { |m| out << [ [ m.id ], m.game, nil, type, Side.new(m, "home"), Side.new(m, "away") ] }
      when "spread" then out.concat(spread_pairs(ms))
      else ms.each { |m| out << [ [ m.id ], m.game, m.player, type, Side.new(m, "over"), Side.new(m, "under") ] }
      end
    end
    out
  end

  def spread_pairs(markets)
    markets.group_by(&:game_id).flat_map do |_, ms|
      away_by_line = ms.select { |m| m.line && m.market_type == "spread" }.index_by(&:line)
      ms.filter_map do |home|
        away = away_by_line[-home.line]
        next if away.nil? || away.id == home.id || home.line.zero?
        next unless home.line.negative? # one pair per spread: anchor on the favourite's line

        [ [ home.id, away.id ], home.game, nil, "spread", Side.new(home, "home"), Side.new(away, "away") ]
      end
    end
  end
end
