module Ev
  # Every price on upcoming games that beats the fair price. One row per (market side): the best-EV book among those enabled.
  class Opportunities
    PER_PAGE = 20
    SORTS = %w[ev kelly].freeze

    Filters = Data.define(:min_ev, :method, :kelly, :min_books, :market_types, :side, :sort, :page) do
      def self.from_params(params)
        p = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h.stringify_keys
        multiplier = BigDecimal(p["kelly"].to_s, exception: false)
        new(
          min_ev: BigDecimal((BigDecimal(p["min_ev"].to_s, exception: false) || 1).clamp(0, 100).to_s), # clamp can return the Integer bound
          method: FairPrice::METHODS.include?(p["method"]) ? p["method"] : "multiplicative",
          kelly: multiplier && multiplier.positive? && multiplier <= 1 ? multiplier : BigDecimal("0.25"),
          min_books: (Integer(p["min_books"].to_s, exception: false) || 3).clamp(2, 9),
          market_types: Array(p["market_types"]).map(&:to_s) & TwoWayMarkets::MARKET_TYPES,
          side: %w[over under].include?(p["side"]) ? p["side"] : nil,
          sort: SORTS.include?(p["sort"]) ? p["sort"] : "ev",
          page: [ Integer(p["page"].to_s, exception: false) || 1, 1 ].max
        )
      end

      def to_query(**o) = { min_ev: min_ev.to_s("F"), method: method, kelly: kelly.to_s("F"), min_books: min_books, market_types: market_types.presence, side: side, sort: sort }.merge(o).compact
    end

    Row = Data.define(:pair, :side, :snap, :bookmaker, :fair_probability, :fair_american, :ev, :kelly, :kind, :books_used, :per_book) do
      def market = pair.side_of(side).market
      def outcome = pair.side_of(side).outcome
      def decimal = snap.decimal_odds
    end
    Result = Data.define(:rows, :total, :page, :pages)

    def self.call(**) = new(**).call

    def initialize(filters:, bookmaker_ids: nil, now: Time.current, paginate: true)
      @f, @bookmaker_ids, @now, @paginate = filters, bookmaker_ids, now, paginate
    end

    def call
      books = Bookmaker.all.index_by(&:id)
      sharp = books.values.select(&:sharp).map(&:id)
      rows = TwoWayMarkets.call(now: @now).flat_map do |pair|
        next [] if @f.market_types.any? && @f.market_types.exclude?(pair.market_type)

        fair = FairPrice.call(pair: pair, method: @f.method, min_books: @f.min_books, sharp_book_ids: sharp)
        fair ? rows_for(pair, fair, books) : []
      end
      rows = rows.select { |r| r.outcome == @f.side } if @f.side
      rows = rows.sort_by { |r| [ -r.public_send(@f.sort), r.market.id ] }
      @paginate ? paginate(rows) : Result.new(rows: rows, total: rows.size, page: 1, pages: 1)
    end

    private

    def rows_for(pair, fair, books)
      %i[left right].filter_map do |side|
        prob = side == :left ? fair.left : fair.right
        candidates = pair.snaps_for(side).reject { |s| (@bookmaker_ids && @bookmaker_ids.exclude?(s.bookmaker_id)) || (fair.kind == :sharp && fair.book_ids.include?(s.bookmaker_id)) }
        best = candidates.max_by(&:decimal_odds) or next
        r = EvCalculator.call(fair_probability: prob, decimal_odds: best.decimal_odds, kelly_multiplier: @f.kelly)
        next if r.ev * 100 < @f.min_ev || r.ev <= 0

        Row.new(pair: pair, side: side, snap: best, bookmaker: books[best.bookmaker_id], fair_probability: prob, fair_american: OddsMath.implied_to_american(prob),
                ev: r.ev, kelly: r.kelly, kind: fair.kind, books_used: fair.book_ids.size, per_book: fair.per_book)
      end
    end

    def paginate(rows)
      pages = [ (rows.size.to_f / PER_PAGE).ceil, 1 ].max
      page = [ @f.page, pages ].min
      Result.new(rows: rows.slice((page - 1) * PER_PAGE, PER_PAGE) || [], total: rows.size, page: page, pages: pages)
    end
  end
end
