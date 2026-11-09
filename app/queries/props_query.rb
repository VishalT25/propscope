# The props explorer: reads ONLY our own tables (markets, latest snapshots, prop_hit_rates, defense_ranks).
# Filters/sort come from URL params so every view is shareable.
class PropsQuery
  PER_PAGE = 50
  WINDOWS = %w[l5 l10 l20 h2h season prev_season].freeze
  SORTS = (%w[line best_odds ip opp_rank] + WINDOWS).freeze
  SIDES = %w[over under].freeze
  TIERS = %w[favorable neutral unfavorable].freeze
  INVERT = { "favorable" => "unfavorable", "unfavorable" => "favorable", "neutral" => "neutral" }.freeze

  Filters = Data.define(:game_ids, :market_types, :q, :side, :odds_min, :odds_max, :min_hit_rate, :hit_window, :tier, :book_keys, :alt, :sort, :dir, :page) do
    def self.from_params(params)
      p = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      list = ->(k) { Array(p[k]).map(&:to_s).reject(&:blank?) }
      int = ->(k) { Integer(p[k].to_s, exception: false) }
      new(
        game_ids: list.("game_ids").filter_map { |v| Integer(v, exception: false) },
        market_types: list.("market_types") & StatCatalog::BY_MARKET.keys,
        q: p["q"].to_s.strip.presence,
        side: SIDES.include?(p["side"]) ? p["side"] : nil,
        odds_min: int.("odds_min"), odds_max: int.("odds_max"),
        min_hit_rate: Integer(p["min_hit_rate"].to_s, exception: false)&.clamp(0, 100),
        hit_window: WINDOWS.include?(p["hit_window"]) ? p["hit_window"] : "l10",
        tier: TIERS.include?(p["tier"]) ? p["tier"] : nil,
        book_keys: list.("book_keys"),
        alt: p["alt"] == "1",
        sort: SORTS.include?(p["sort"]) ? p["sort"] : "l10",
        dir: p["dir"] == "asc" ? "asc" : "desc",
        page: [ int.("page") || 1, 1 ].max
      )
    end

    # Number of filters the user has set (the "Current filters" badge). Sort and page do not count.
    def active_count
      [ game_ids.any?, market_types.any?, q, side, odds_min || odds_max, min_hit_rate, tier, book_keys.any?, alt ].count { |v| v }
    end

    # Params that survive a link (used for sort and pagination links).
    def to_query(**overrides)
      h = { game_ids: game_ids.presence, market_types: market_types.presence, q: q, side: side, odds_min: odds_min, odds_max: odds_max,
            min_hit_rate: min_hit_rate, hit_window: (hit_window unless hit_window == "l10" && min_hit_rate.nil?), tier: tier,
            book_keys: book_keys.presence, alt: ("1" if alt), sort: sort, dir: dir }.merge(overrides)
      h.compact
    end
  end

  Row = Data.define(:market, :side, :player, :game, :line, :price, :implied, :hit, :opp_rank, :tier) do
    def team = player.team
    def opponent = game.home_team_id == player.team_id ? game.away_team : game.home_team
    def home? = game.home_team_id == player.team_id
    def rate(window) = hit&.public_send(window)
    def sample(window) = hit&.public_send("#{window}_n")
    def stat = StatCatalog.for_market(market.market_type)
  end

  Result = Data.define(:rows, :total, :page, :pages, :updated_at)

  def self.call(**) = new(**).call

  def initialize(filters:, bookmaker_ids: nil, now: Time.current, paginate: true)
    @f = filters
    @bookmaker_ids = bookmaker_ids
    @now = now
    @paginate = paginate
  end

  def call
    markets = candidate_markets
    ids = markets.map(&:id)
    prices = BestPrice.for(market_ids: ids, bookmaker_ids: effective_book_ids)
    hits = PropHitRate.where(market_id: ids).index_by { |h| [ h.market_id, h.side ] }
    ranks = defense_ranks(markets)

    rows = markets.flat_map { |m| sides.filter_map { |side| build_row(m, side, prices, hits, ranks) } }
    rows = filter(rows)
    rows = sort(rows)
    total = rows.size
    pages = [ (total.to_f / PER_PAGE).ceil, 1 ].max
    page = [ @f.page, pages ].min
    rows = rows.slice((page - 1) * PER_PAGE, PER_PAGE) || [] if @paginate
    Result.new(rows: rows, total: total, page: page, pages: pages, updated_at: PropHitRate.where(market_id: ids).maximum(:computed_at))
  end

  # Games on the slate that can still be bet (for the filter drawer).
  def self.upcoming_games(now: Time.current)
    Game.where(starts_at: now..).includes(:home_team, :away_team).order(:starts_at)
  end

  private

  def sides = @f.side ? [ @f.side ] : SIDES

  def effective_book_ids
    return @bookmaker_ids if @f.book_keys.empty?

    keys = Bookmaker.where(key: @f.book_keys).pluck(:id)
    @bookmaker_ids ? (keys & @bookmaker_ids) : keys
  end

  def candidate_markets
    scope = Market.joins(:game).where(games: { starts_at: @now.. }).where.not(player_id: nil)
                  .where(market_type: StatCatalog::BY_MARKET.keys).includes(:player, game: %i[home_team away_team])
    scope = scope.where(is_alternate: false) unless @f.alt
    scope = scope.where(game_id: @f.game_ids) if @f.game_ids.any?
    scope = scope.where(market_type: @f.market_types) if @f.market_types.any?
    if @f.q
      term = "%#{Market.sanitize_sql_like(NameNormalizer.call(@f.q))}%"
      scope = scope.joins(:player).where("players.normalized_name LIKE ?", term)
    end
    scope.includes(player: :team).to_a
  end

  def defense_ranks(markets)
    return {} if markets.empty?

    season = markets.first.game.season
    DefenseRank.where(season: season).index_by { |r| [ r.team_id, r.stat, r.position ] }
  end

  def build_row(market, side, prices, hits, ranks)
    price = prices[[ market.id, side ]] or return nil
    player = market.player
    game = market.game
    return nil unless player.team_id && [ game.home_team_id, game.away_team_id ].include?(player.team_id)

    opponent_id = game.home_team_id == player.team_id ? game.away_team_id : game.home_team_id
    stat = StatCatalog.for_market(market.market_type)
    rank = ranks[[ opponent_id, stat.defense_stat, StatCatalog.position_bucket(player.position) ]]
    tier = rank && (side == "under" ? INVERT.fetch(rank.tier) : rank.tier)
    Row.new(market: market, side: side, player: player, game: game, line: market.line, price: price,
            implied: OddsMath.american_to_implied(price.american_odds), hit: hits[[ market.id, side ]], opp_rank: rank, tier: tier)
  end

  def filter(rows)
    rows = rows.select { |r| r.price.decimal_odds >= decimal_bound(@f.odds_min) } if @f.odds_min
    rows = rows.select { |r| r.price.decimal_odds <= decimal_bound(@f.odds_max) } if @f.odds_max
    rows = rows.select { |r| (rate = r.rate(@f.hit_window)) && r.sample(@f.hit_window).to_i >= ApplicationHelper::MIN_SAMPLE && rate >= @f.min_hit_rate } if @f.min_hit_rate
    rows = rows.select { |r| r.tier == @f.tier } if @f.tier
    rows
  end

  # American odds bound (e.g. -150) as a decimal price. Values in (-100, 100) are not valid American odds: ignore them.
  def decimal_bound(american)
    american.abs >= 100 ? OddsMath.american_to_decimal(american) : BigDecimal(american >= 0 ? "-Infinity" : "Infinity")
  end

  def sort(rows)
    dir = @f.dir == "asc" ? 1 : -1
    key = sort_key(@f.sort)
    present, missing = rows.partition { |r| key.call(r) }
    present.sort_by { |r| [ dir * key.call(r), r.player.last_name, r.market.id ] }.then { |s| s + missing }
  end

  def sort_key(name)
    case name
    when "line" then ->(r) { r.line }
    when "best_odds" then ->(r) { r.price.decimal_odds }
    when "ip" then ->(r) { r.implied }
    when "opp_rank" then ->(r) { r.opp_rank&.rank }
    else ->(r) { r.sample(name).to_i >= ApplicationHelper::MIN_SAMPLE ? r.rate(name) : nil }
    end
  end
end
