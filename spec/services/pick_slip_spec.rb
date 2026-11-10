require "rails_helper"

RSpec.describe PickSlip do
  let(:user) { create(:user) }
  let(:fd) { create(:bookmaker, key: "fd", code: "FD", name: "FanDuel") }
  let(:dk) { create(:bookmaker, key: "dk", code: "DK", name: "DraftKings") }
  let(:game) { create(:game, starts_at: 5.hours.from_now) }

  def leg(odds_by_book, side: "over", line: 24.5, game: self.game, add_at: nil)
    player = create(:player, sport: game.sport, team: game.home_team)
    market = create(:market, game: game, player: player, market_type: "player_points", line: line)
    odds_by_book.each do |book, (price, deeplink)|
      create(:odds_snapshot, market: market, bookmaker: book, outcome: side, american_odds: price, decimal_odds: OddsMath.american_to_decimal(price), line: line, deeplink: deeplink)
    end
    first = odds_by_book.keys.first
    user.picks.create!(market: market, side: side, bookmaker: first, price_at_add: add_at || odds_by_book[first][0])
    market
  end

  def slip(**o) = described_class.call(user: user, **o)

  it "is empty for a new user" do
    s = slip
    expect([ s.legs, s.parlay, s.options ]).to eq([ [], nil, [] ])
  end

  it "prices each leg at its best book and multiplies the legs into parlay odds" do
    leg({ fd => [ 110 ], dk => [ 120 ] })      # best: +120 (2.20)
    leg({ fd => [ -110 ], dk => [ -105 ] })    # best: -105 (1.9524)
    s = slip(stake: 10)
    expect(s.legs.map { |l| l.chosen.bookmaker }).to eq([ dk, dk ])
    expect(s.parlay.decimal).to eq((BigDecimal("2.2") * BigDecimal("1.9524")).round(4))
    expect(s.parlay.american).to eq(OddsMath.decimal_to_american(s.parlay.decimal))
    expect(s.parlay.payout).to eq((10 * s.parlay.decimal).round(2))
    expect(s.parlay.profit).to eq(s.parlay.payout - 10)
    expect(s.parlay.legs).to eq(2)
  end

  it "prices every leg at the chosen book" do
    leg({ fd => [ 110 ], dk => [ 120 ] })
    leg({ fd => [ -110 ], dk => [ -105 ] })
    s = slip(book_key: "fd", stake: 25)
    expect(s.book).to eq(fd)
    expect(s.legs.map { |l| l.chosen.american_odds }).to eq([ 110, -110 ])
    expect(s.parlay.decimal).to eq((BigDecimal("2.1") * BigDecimal("1.9091")).round(4))
    expect(s.parlay.payout).to eq((25 * s.parlay.decimal).round(2))
  end

  it "has no combined odds, and names the legs, when the chosen book does not offer one" do
    leg({ fd => [ 110 ], dk => [ 120 ] })
    only_dk = leg({ dk => [ -105 ] })
    s = slip(book_key: "fd")
    expect(s.parlay).to be_nil
    expect(s.missing.map(&:market)).to eq([ only_dk ])
  end

  it "ranks books by what they would pay for the WHOLE slip, and says which legs a book lacks" do
    leg({ fd => [ 110 ], dk => [ 120 ] })
    leg({ dk => [ -105 ] })
    s = slip
    expect(s.options.first).to have_attributes(bookmaker: dk, legs_offered: 2, total: 2)
    expect(s.best_option.bookmaker).to eq(dk)
    fd_option = s.options.find { |o| o.bookmaker == fd }
    expect([ fd_option.legs_offered, fd_option.decimal, fd_option.american ]).to eq([ 1, nil, nil ])
  end

  it "treats a single leg as a single bet" do
    leg({ fd => [ 150 ] })
    s = slip(stake: 20)
    expect(s.parlay.legs).to eq(1)
    expect(s.parlay.payout).to eq(50)
    expect(s.parlay.profit).to eq(30)
  end

  it "flags legs from the same game" do
    leg({ fd => [ 110 ] })
    leg({ fd => [ 110 ] })
    expect(slip.same_game).to be(true)
    other = create(:game, starts_at: 6.hours.from_now)
    user.picks.destroy_all
    leg({ fd => [ 110 ] })
    leg({ fd => [ 110 ] }, game: other)
    expect(slip.same_game).to be(false)
  end

  it "shows how the price moved since the leg was added (current price, not the stale one)" do
    market = leg({ fd => [ 110 ] }, add_at: 100)
    expect(slip.legs.first.moved).to eq(1)       # better than when added
    create(:odds_snapshot, market: market, bookmaker: fd, outcome: "over", american_odds: -120, decimal_odds: OddsMath.american_to_decimal(-120), captured_at: 1.minute.from_now)
    expect(slip.legs.first.chosen.american_odds).to eq(-120)
    expect(slip.legs.first.moved).to eq(-1)
  end

  it "carries the book's own betslip link when we have one" do
    leg({ fd => [ 110, "https://book.test/add?x=1" ] })
    expect(slip.legs.first.chosen.deeplink).to eq("https://book.test/add?x=1")
  end

  it "clamps the stake and survives junk" do
    leg({ fd => [ 110 ] })
    expect(slip(stake: "abc").stake).to eq(10)
    expect(slip(stake: "-5").stake).to eq(1)
    expect(slip(stake: "999999999").stake).to eq(PickSlip::MAX_STAKE)
    expect(slip(book_key: "no-such-book").book).to be_nil
  end

  it "keeps a leg with no current price visible but unpriced" do
    market = leg({ fd => [ 110 ] })
    OddsSnapshot.where(market: market).delete_all
    s = slip
    expect(s.legs.size).to eq(1)
    expect(s.parlay).to be_nil
  end
end
