module Insights
  # Joins stored insights with what the cards show: best price and the last-10 hit/miss strip.
  class Feed
    Row = Data.define(:insight, :market, :player, :game, :stat, :price, :outcomes, :rate)
    PER_PAGE = 20

    def self.call(**) = new(**).call

    # filters: game_id, team_id, q (player name), market_type, page
    def initialize(filters: {}, bookmaker_ids: nil, now: Time.current)
      @f = filters
      @bookmaker_ids = bookmaker_ids
      @now = now
    end

    Result = Data.define(:rows, :total, :page, :pages)

    def call
      scope = Insight.joins(:market, :game).where(games: { starts_at: @now.. }).order(strength: :desc, id: :asc)
      scope = scope.where(game_id: @f[:game_id]) if @f[:game_id].present?
      scope = scope.where(markets: { market_type: @f[:market_type] }) if StatCatalog::BY_MARKET.key?(@f[:market_type].to_s)
      if @f[:team_id].present?
        scope = scope.joins("JOIN players ON players.id = insights.subject_id").where(players: { team_id: @f[:team_id] })
      end
      if @f[:q].present?
        scope = scope.joins("JOIN players pn ON pn.id = insights.subject_id").where("pn.normalized_name LIKE ?", "%#{Insight.sanitize_sql_like(NameNormalizer.call(@f[:q]))}%")
      end
      total = scope.count
      pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
      page = (@f[:page].to_i.clamp(1, pages))
      insights = scope.includes(market: [ { player: :team }, :game ]).offset((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
      Result.new(rows: rows_for(insights), total: total, page: page, pages: pages)
    end

    private

    def rows_for(insights)
      prices = BestPrice.for(market_ids: insights.map(&:market_id).uniq, bookmaker_ids: @bookmaker_ids)
      logs = PlayerGameLog.played.where(player_id: insights.map { |i| i.market.player_id }.uniq).to_a.group_by(&:player_id)
      insights.filter_map do |i|
        m = i.market
        stat = StatCatalog.for_market(m.market_type)
        values = HitRateCalculator.game_values(logs[m.player_id] || [], stat)
        outcomes = HitRateCalculator.outcomes(games: values, line: m.line, side: i.side)
        decided = outcomes.compact
        Row.new(insight: i, market: m, player: m.player, game: m.game, stat: stat, price: prices[[ m.id, i.side ]], outcomes: outcomes,
                rate: decided.empty? ? nil : BigDecimal(decided.count(true)) * 100 / decided.size)
      end
    end
  end
end
