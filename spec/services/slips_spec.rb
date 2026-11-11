require "rails_helper"

RSpec.describe "Saved slips" do
  let(:user) { create(:user) }
  let(:book) { create(:bookmaker, key: "fd", code: "FD", name: "FanDuel") }
  let(:game) { create(:game, starts_at: 2.hours.ago) }

  # A saved slip with one leg per [side, line, decimal odds, market_type] entry, each on its own player in `game`.
  def saved_slip(*specs, stake: 10, game: self.game)
    slip = user.slips.create!(name: "Test", stake: stake, decimal_odds: 2, bookmaker: book)
    specs.map do |side, line, decimal, type|
      decimal = BigDecimal(decimal.to_s) # never a Float: OddsMath refuses them
      player = create(:player, sport: game.sport, team: game.home_team)
      market = create(:market, game: game, player: player, market_type: type || "player_points", line: line)
      slip.legs.create!(market: market, bookmaker: book, side: side, line: line, american_odds: OddsMath.decimal_to_american(decimal), decimal_odds: decimal)
    end
    slip.reload
  end

  def log_for(leg, **stats) = create(:player_game_log, player: leg.market.player, game: leg.market.game, **stats)

  describe Slips::Grade do
    it "marks an over a hit, a miss or a push against the line saved with the leg" do
      slip = saved_slip([ "over", 24.5, 1.9 ], [ "over", 24.5, 1.9 ], [ "over", 25, 1.9 ])
      log_for(slip.legs[0], points: 30)
      log_for(slip.legs[1], points: 20)
      log_for(slip.legs[2], points: 25)

      expect(described_class.call).to eq(3)
      expect(slip.legs.reload.map { |l| [ l.result, l.actual.to_i ] }).to eq([ [ "hit", 30 ], [ "miss", 20 ], [ "push", 25 ] ])
      expect(slip.legs.map(&:graded_at)).to all(be_present)
    end

    it "flips the result for an under" do
      slip = saved_slip([ "under", 24.5, 1.9 ])
      log_for(slip.legs.first, points: 20)
      described_class.call
      expect(slip.legs.first.reload.result).to eq("hit")
    end

    it "uses the stat the market is settled on (PRA adds points, rebounds and assists)" do
      slip = saved_slip([ "over", 30.5, 1.9, "player_pra" ])
      log_for(slip.legs.first, points: 20, rebounds: 8, assists: 5)
      described_class.call
      expect(slip.legs.first.reload.then { |l| [ l.result, l.actual.to_i ] }).to eq([ "hit", 33 ])
    end

    it "voids a leg whose player did not play (0 minutes), and a leg in a postponed game" do
      slip = saved_slip([ "over", 24.5, 1.9 ])
      log_for(slip.legs.first, minutes: 0, points: 0)
      postponed = saved_slip([ "over", 24.5, 1.9 ], game: create(:game, status: "postponed"))
      described_class.call
      expect(slip.legs.first.reload.result).to eq("void")
      expect(postponed.legs.first.reload.result).to eq("void")
    end

    it "leaves a leg pending until its box score exists, and never regrades a settled one" do
      slip = saved_slip([ "over", 24.5, 1.9 ])
      expect(described_class.call).to eq(0)
      expect(slip.legs.first.reload.result).to be_nil

      log = log_for(slip.legs.first, points: 30)
      described_class.call
      log.update!(points: 10) # a later correction must not rewrite history
      expect(described_class.call).to eq(0)
      expect(slip.legs.first.reload.result).to eq("hit")
    end
  end

  describe Slips::Settlement do
    def settle(*results, stake: 10, decimals: nil)
      slip = saved_slip(*results.each_index.map { |i| [ "over", 24.5, decimals ? decimals[i] : 2 ] }, stake: stake)
      slip.legs.zip(results).each { |leg, r| leg.update!(result: r) }
      described_class.call(slip.reload)
    end

    it "is pending while any leg has no result and nothing has missed" do
      expect(settle("hit", nil).status).to eq(:pending)
    end

    it "is lost as soon as one leg misses, even with games still to play" do
      r = settle("hit", "miss", nil)
      expect([ r.status, r.payout, r.profit ]).to eq([ :lost, 0, -10 ])
    end

    it "pays the stake times the product of the hit legs' prices" do
      r = settle("hit", "hit", decimals: [ BigDecimal("1.9"), BigDecimal("2.1") ])
      expect([ r.status, r.decimal, r.payout, r.profit ]).to eq([ :won, BigDecimal("3.99"), BigDecimal("39.9"), BigDecimal("29.9") ])
    end

    it "drops pushed and void legs out of the parlay" do
      r = settle("hit", "push", "void", decimals: [ BigDecimal("1.9"), BigDecimal("3"), BigDecimal("3") ])
      expect([ r.status, r.decimal, r.payout ]).to eq([ :won, BigDecimal("1.9"), BigDecimal("19") ])
    end

    it "returns the stake when nothing hit" do
      r = settle("push", "void")
      expect([ r.status, r.payout, r.profit ]).to eq([ :push, 10, 0 ])
    end
  end

  describe Slips::Save do
    let(:fd) { book }
    let(:future) { create(:game, starts_at: 5.hours.from_now) }

    def pick(price, book: fd)
      market = create(:market, game: future, player: create(:player, sport: future.sport, team: future.home_team), line: 24.5)
      create(:odds_snapshot, market: market, bookmaker: book, outcome: "over", american_odds: price, decimal_odds: OddsMath.american_to_decimal(price), line: 24.5)
      user.picks.create!(market: market, side: "over", bookmaker: book, price_at_add: price)
      market
    end

    it "snapshots the book, stake, and each leg's line and price, and leaves the working slip alone" do
      pick(110)
      pick(-120)
      working = PickSlip.call(user: user, book_key: "fd", stake: 25)
      saved = described_class.call(user: user, slip: working, name: "Friday")

      expect([ saved.name, saved.bookmaker, saved.stake, saved.decimal_odds ]).to eq([ "Friday", fd, 25, working.parlay.decimal ])
      expect(saved.legs.map { |l| [ l.line, l.american_odds, l.bookmaker ] }).to eq([ [ 24.5, 110, fd ], [ 24.5, -120, fd ] ])
      expect(user.picks.count).to eq(2)
    end

    it "keeps the saved price when the market later moves" do
      market = pick(110)
      saved = described_class.call(user: user, slip: PickSlip.call(user: user, book_key: "fd"))
      create(:odds_snapshot, market: market, bookmaker: fd, outcome: "over", american_odds: 150, decimal_odds: 2.5, line: 24.5, captured_at: 1.minute.from_now)
      expect(saved.legs.first.reload.american_odds).to eq(110)
    end

    it "names a slip by its size when no name is given" do
      pick(110)
      pick(100)
      expect(described_class.call(user: user, slip: PickSlip.call(user: user, book_key: "fd")).name).to eq("2-leg parlay")
    end

    it "refuses an empty slip, and one with a leg the chosen book is not offering" do
      expect { described_class.call(user: user, slip: PickSlip.call(user: user)) }.to raise_error(Slips::Save::Unpriced, /Add a leg/)
      offered = pick(110)
      pick(-120)
      other = create(:bookmaker, key: "dk", code: "DK")
      create(:odds_snapshot, market: offered, bookmaker: other, outcome: "over", american_odds: 115, decimal_odds: OddsMath.american_to_decimal(115), line: 24.5)
      expect { described_class.call(user: user, slip: PickSlip.call(user: user, book_key: other.key)) }.to raise_error(Slips::Save::Unpriced, /current price/)
      expect(Slip.count).to eq(0)
    end
  end
end
