require "rails_helper"

RSpec.describe "EV and arbitrage services" do
  let(:b) { books(5) }
  let(:even_prices) { b.to_h { |book| [ book, [ -110, -110 ] ] } }

  describe TwoWayMarkets do
    it "pairs over/under of props and totals, home/away of moneylines, and home(L) with away(-L) for spreads" do
      game = game_for_two_way
      prop = prop_with_prices(even_prices.first(2).to_h, game: game)
      total = create(:market, game: game, player: nil, market_type: "total", line: 220.5)
      post_prices(total, { b[0] => [ -110, -110 ] })
      ml = create(:market, game: game, player: nil, market_type: "moneyline", line: nil)
      [ [ "home", -150 ], [ "away", 130 ] ].each { |o, p| create(:odds_snapshot, market: ml, bookmaker: b[0], outcome: o, american_odds: p, decimal_odds: OddsMath.american_to_decimal(p), line: nil) }
      home_sp = create(:market, game: game, player: nil, market_type: "spread", line: -3.5)
      away_sp = create(:market, game: game, player: nil, market_type: "spread", line: 3.5)
      create(:odds_snapshot, market: home_sp, bookmaker: b[0], outcome: "home", american_odds: -110, decimal_odds: OddsMath.american_to_decimal(-110), line: -3.5)
      create(:odds_snapshot, market: away_sp, bookmaker: b[1], outcome: "away", american_odds: -105, decimal_odds: OddsMath.american_to_decimal(-105), line: 3.5)

      pairs = described_class.call.index_by(&:market_type)
      expect(pairs.keys).to match_array(%w[player_points total moneyline spread])
      expect(pairs["player_points"].left.market).to eq(prop)
      expect([ pairs["spread"].left.market, pairs["spread"].right.market ]).to eq([ home_sp, away_sp ])
      expect(pairs["moneyline"].left.outcome).to eq("home")
    end

    it "skips a market with only one side priced, alternates and started games" do
      game = game_for_two_way
      one_sided = create(:market, game: game, player: create(:player, sport: game.sport, team: game.home_team), line: 10.5)
      create(:odds_snapshot, market: one_sided, bookmaker: b[0], outcome: "over")
      prop_with_prices(even_prices, game: game).update!(is_alternate: true)
      started = create(:game, starts_at: 1.hour.ago)
      prop_with_prices(even_prices, game: started)
      expect(described_class.call).to be_empty
    end
  end

  describe Ev::FairPrice do
    def pair_for(prices) = TwoWayMarkets.call.find { |p| p.market_type == "player_points" }.tap { prop_with_prices(prices) if false }

    it "uses the average no-vig price of the books (consensus) and sums to 100%" do
      prop_with_prices({ b[0] => [ -120, 100 ], b[1] => [ -110, -110 ], b[2] => [ -115, -105 ] })
      pair = TwoWayMarkets.call.first
      fair = described_class.call(pair: pair, min_books: 3)
      expect(fair.kind).to eq(:consensus)
      expect(fair.left + fair.right).to eq(1)
      expect(fair.left).to be_between(BigDecimal("0.50"), BigDecimal("0.55"))
      expect(fair.per_book.size).to eq(3)
    end

    it "needs enough books for a consensus" do
      prop_with_prices({ b[0] => [ -110, -110 ], b[1] => [ -112, -108 ] })
      expect(described_class.call(pair: TwoWayMarkets.call.first, min_books: 3)).to be_nil
      expect(described_class.call(pair: TwoWayMarkets.call.first, min_books: 2)).not_to be_nil
    end

    it "prefers a sharp book, even a single one, over the consensus" do
      sharp = create(:bookmaker, key: "sharp-#{SecureRandom.hex(2)}", code: "SH", sharp: true)
      prop_with_prices({ b[0] => [ 100, -120 ], b[1] => [ 100, -120 ], b[2] => [ 100, -120 ], sharp => [ -125, 105 ] })
      fair = described_class.call(pair: TwoWayMarkets.call.first, min_books: 3, sharp_book_ids: [ sharp.id ])
      expect(fair.kind).to eq(:sharp)
      expect(fair.book_ids).to eq([ sharp.id ])
      expect(fair.left).to be_between(BigDecimal("0.52"), BigDecimal("0.54")) # the sharp book likes the over; the soft books (about 47.8%) do not
    end

    it "supports the power method, which shades the longshot more than multiplicative" do
      prop_with_prices({ b[0] => [ -500, 380 ], b[1] => [ -500, 380 ], b[2] => [ -500, 380 ] })
      pair = TwoWayMarkets.call.first
      mult = described_class.call(pair: pair, method: "multiplicative")
      power = described_class.call(pair: pair, method: "power")
      expect(power.right).to be < mult.right
      expect(power.left + power.right).to eq(1)
    end

    it "falls back to multiplicative for an unknown method" do
      prop_with_prices(even_prices)
      pair = TwoWayMarkets.call.first
      expect(described_class.call(pair: pair, method: "bogus").left).to eq(described_class.call(pair: pair).left)
    end
  end

  describe EvCalculator do
    it "computes EV and quarter Kelly" do
      r = described_class.call(fair_probability: BigDecimal("0.55"), decimal_odds: BigDecimal("2.0"))
      expect(r.ev).to eq(BigDecimal("0.1"))
      expect(r.kelly).to eq(BigDecimal("0.025"))
    end

    it "has no Kelly stake without an edge" do
      expect(described_class.call(fair_probability: BigDecimal("0.4"), decimal_odds: BigDecimal("2.0")).kelly).to eq(0)
    end
  end

  describe Ev::Opportunities do
    def run(**p) = described_class.call(filters: Ev::Opportunities::Filters.from_params(p), bookmaker_ids: p[:book_ids])

    # fair is about 50/50; one book is generous on the over, one on the under
    before { prop_with_prices({ b[0] => [ -110, -110 ], b[1] => [ -110, -110 ], b[2] => [ -110, -110 ], b[3] => [ 120, -150 ], b[4] => [ -150, 120 ] }) }

    it "returns the best-EV book for each side of a market, with EV and Kelly" do
      rows = run(min_books: 3).rows
      expect(rows.map(&:outcome)).to contain_exactly("over", "under")
      over = rows.find { |r| r.outcome == "over" }
      expect(over.bookmaker).to eq(b[3])
      expect(over.snap.american_odds).to eq(120)
      expect(over.ev).to be > BigDecimal("0.05")
      expect(over.kelly).to be > 0
      expect(over.kind).to eq(:consensus)
      expect(over.books_used).to eq(5)
      expect(over.fair_american).to be_between(-130, 130)
    end

    it "sorts best first and honours the minimum EV" do
      rows = run(min_books: 3).rows
      expect(rows.map(&:ev)).to eq(rows.map(&:ev).sort.reverse)
      expect(run(min_ev: 90).rows).to be_empty
      expect(run(min_ev: 0.5).total).to be >= run(min_ev: 5).total
    end

    it "filters by side and market type" do
      expect(run(side: "under").rows.map(&:outcome).uniq).to eq([ "under" ])
      expect(run(market_types: [ "player_assists" ]).rows).to be_empty
    end

    it "only offers books the user enabled, but still builds the fair price from all of them" do
      rows = run(book_ids: [ b[4].id ]).rows
      expect(rows.map(&:bookmaker).uniq).to eq([ b[4] ])
      expect(rows.first.books_used).to eq(5)
    end

    it "never offers the sharp book itself against its own fair price" do
      b[0].update!(sharp: true)
      expect(run.rows.map(&:bookmaker)).not_to include(b[0])
      expect(run.rows.map(&:kind).uniq).to eq([ :sharp ])
    end

    it "is empty without enough books for a fair price" do
      expect(run(min_books: 9).rows).to be_empty
    end

    it "paginates and survives bad params" do
      expect(run(min_ev: "abc", method: "zzz", kelly: "99", min_books: "-4", side: "x", sort: "evil", page: "-1").total).to be >= 0
      filters = Ev::Opportunities::Filters.from_params(kelly: "99", min_books: "100", min_ev: "500")
      expect([ filters.kelly, filters.min_books, filters.min_ev ]).to eq([ BigDecimal("0.25"), 9, 100 ])
      expect { filters.min_ev.to_s("F") }.not_to raise_error # a clamped value must still be a BigDecimal
    end

    it "orders by Kelly when asked" do
      rows = run(sort: "kelly").rows
      expect(rows.map(&:kelly)).to eq(rows.map(&:kelly).sort.reverse)
    end
  end

  describe ArbitrageFinder do
    it "finds a market whose best prices at two different books imply under 100%, and ranks by margin" do
      prop_with_prices({ b[0] => [ 115, -140 ], b[1] => [ -140, 108 ] })   # +115 / +108: arbitrage
      prop_with_prices({ b[2] => [ 105, -125 ], b[3] => [ -125, 101 ] }, line: 10.5) # +105 / +101: smaller
      rows = described_class.call
      expect(rows.size).to eq(2)
      expect(rows.map(&:profit)).to eq(rows.map(&:profit).sort.reverse)
      expect(rows.first.left_snap.american_odds).to eq(115)
      expect(rows.first.profit).to be > BigDecimal("0.03")
    end

    it "never reports a single book against itself, or a market with no gap" do
      prop_with_prices({ b[0] => [ 105, 105 ] })              # one book pricing both sides (a data error): not an arb to take
      prop_with_prices(even_prices, line: 12.5)               # normal vig everywhere
      expect(described_class.call).to be_empty
    end

    it "respects the enabled books and the minimum margin" do
      prop_with_prices({ b[0] => [ 115, -140 ], b[1] => [ -140, 108 ] })
      expect(described_class.call(bookmaker_ids: [ b[0].id ])).to be_empty
      expect(described_class.call(min_profit: BigDecimal(50))).to be_empty
    end

    it "splits any stake into whole cents whose payouts match within a cent or two" do
      prop_with_prices({ b[0] => [ 115, -140 ], b[1] => [ -140, 108 ] })
      row = described_class.call.first
      [ "100", "250.55", "37.31", "1000" ].each do |stake|
        split = row.split(stake)
        expect(split.sum { |s| s[:stake] }).to eq(BigDecimal(stake))
        payouts = split.map { |s| s[:payout] }
        expect(payouts.max - payouts.min).to be <= BigDecimal("0.02")
        expect(payouts.min).to be > BigDecimal(stake) # a real arbitrage returns more than was staked, whichever side wins
      end
    end
  end
end
