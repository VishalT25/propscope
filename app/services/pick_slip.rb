# The My Picks slip as a parlay builder. Each pick is a LEG (a market and a side). Choose a book and every leg is priced at
# that book's CURRENT price; the combined odds and payout are calculated for you. With no book chosen each leg uses its
# best price across books. Nothing here places a bet: you export the slip (copy it, or open each leg at the book).
class PickSlip
  MAX_STAKE = BigDecimal(100_000)

  Leg = Data.define(:pick, :market, :player, :game, :stat, :offers, :chosen, :best, :price_at_add, :moved) do
    def snap = chosen # the price this leg is priced at on the slip
  end
  Option = Data.define(:bookmaker, :legs_offered, :total, :decimal, :american) # decimal/american nil unless the book offers every leg
  Parlay = Data.define(:decimal, :american, :implied, :stake, :payout, :profit, :legs)
  Slip = Data.define(:legs, :book, :stake, :parlay, :missing, :options, :best_option, :same_game)

  def self.call(**) = new(**).call

  def initialize(user:, book_key: nil, stake: nil)
    @user = user
    @book_key = book_key.presence
    @stake = normalize_stake(stake)
  end

  def call
    picks = @user.picks.includes(market: [ :game, { player: :team } ]).order(:created_at).to_a
    current = BestPrice.current_snapshots(market_ids: picks.map(&:market_id).uniq).group_by { |s| [ s.market_id, s.outcome ] }
    books = Bookmaker.where(id: current.values.flatten.map(&:bookmaker_id).uniq).index_by(&:id)
    book = books.values.find { |b| b.key == @book_key }
    legs = picks.map { |pick| leg_for(pick, current[[ pick.market_id, pick.side ]] || [], book) }
    Slip.new(legs: legs, book: book, stake: @stake, parlay: parlay(legs), missing: legs.reject(&:chosen), options: options(legs, books),
             best_option: nil, same_game: legs.map { |l| l.game.id }.uniq.size < legs.size).then { |s| s.with(best_option: s.options.select(&:decimal).max_by(&:decimal)) }
  end

  private

  def normalize_stake(value)
    d = BigDecimal(value.to_s, exception: false) || BigDecimal(10)
    BigDecimal(d.clamp(1, MAX_STAKE).to_s)
  end

  def leg_for(pick, offers, book)
    best = offers.max_by { |s| [ s.decimal_odds, s.captured_at ] }
    chosen = book ? offers.find { |s| s.bookmaker_id == book.id } : best
    m = pick.market
    moved = chosen && (chosen.decimal_odds <=> OddsMath.american_to_decimal(pick.price_at_add))
    Leg.new(pick: pick, market: m, player: m.player, game: m.game, stat: StatCatalog.for_market(m.market_type), offers: offers.index_by(&:bookmaker_id),
            chosen: chosen, best: best, price_at_add: pick.price_at_add, moved: moved)
  end

  # Combined odds are the product of the legs' decimal odds. Only when every leg is priced.
  def parlay(legs)
    return nil if legs.empty? || legs.any? { |l| l.chosen.nil? }

    decimal = legs.map { |l| l.chosen.decimal_odds }.reduce(:*).round(4)
    Parlay.new(decimal: decimal, american: OddsMath.decimal_to_american(decimal), implied: (BigDecimal(1) / decimal).round(6), stake: @stake,
               payout: (@stake * decimal).round(2), profit: (@stake * (decimal - 1)).round(2), legs: legs.size)
  end

  # How each book would price the whole slip, best first.
  def options(legs, books)
    return [] if legs.empty?

    books.values.map do |b|
      snaps = legs.map { |l| l.offers[b.id] }
      full = snaps.all?
      decimal = full ? snaps.map(&:decimal_odds).reduce(:*).round(4) : nil
      Option.new(bookmaker: b, legs_offered: snaps.compact.size, total: legs.size, decimal: decimal, american: decimal && OddsMath.decimal_to_american(decimal))
    end.sort_by { |o| [ o.decimal ? 0 : 1, -(o.decimal || 0), -o.legs_offered, o.bookmaker.name ] }
  end
end
