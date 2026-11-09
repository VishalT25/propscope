require "rails_helper"

RSpec.describe HitRateCalculator do
  def gv(value, days_ago: 1, season: 2026, opponent: 1, minutes: 30, game_id: nil)
    described_class::GameValue.new(date: Date.new(2026, 11, 9) - days_ago, season: season, opponent_id: opponent, value: value, minutes: minutes, game_id: game_id)
  end

  def run(values, line: 20.5, side: "over", opponent_id: 1, season: 2026)
    described_class.call(games: values, line: line, side: side, opponent_id: opponent_id, current_season: season)
  end

  describe "hit / miss / push" do
    it "over hits above the line, under hits below it" do
      games = [ gv(25), gv(15, days_ago: 2), gv(21, days_ago: 3) ]
      expect(run(games, side: "over").windows[:l5]).to have_attributes(hits: 2, misses: 1, pushes: 0, rate: BigDecimal("66.67"))
      expect(run(games, side: "under").windows[:l5]).to have_attributes(hits: 1, misses: 2, rate: BigDecimal("33.33"))
    end

    it "excludes pushes from the denominator and counts them separately" do
      games = [ gv(20), gv(25, days_ago: 2), gv(10, days_ago: 3), gv(20, days_ago: 4) ]
      w = run(games, line: 20).windows[:l5]
      expect([ w.hits, w.misses, w.pushes, w.n ]).to eq([ 1, 1, 2, 2 ])
      expect(w.rate).to eq(50)
    end

    it "handles half-point and whole-number lines (decimals never become floats)" do
      expect(run([ gv(21) ], line: BigDecimal("20.5")).windows[:l5].hits).to eq(1)
      expect(run([ gv(20) ], line: 20).windows[:l5].pushes).to eq(1)
    end

    it "has a nil rate (not zero) when nothing is decided" do
      expect(run([ gv(20) ], line: 20).windows[:l5].rate).to be_nil
      expect(run([]).windows[:l10].rate).to be_nil
    end
  end

  describe "DNP handling" do
    it "ignores zero-minute games entirely, so they neither hit nor fill the window" do
      games = (1..6).map { |i| gv(30, days_ago: i) } + [ gv(0, days_ago: 0, minutes: 0) ]
      w = run(games, line: 20.5).windows[:l5]
      expect(w.n).to eq(5)
      expect(w.rate).to eq(100)
    end

    it "pulls an older game into L5 when a recent one was a DNP" do
      games = [ gv(0, days_ago: 1, minutes: 0), gv(30, days_ago: 2), gv(30, days_ago: 3), gv(30, days_ago: 4), gv(30, days_ago: 5), gv(30, days_ago: 6) ]
      expect(run(games).windows[:l5].n).to eq(5)
    end
  end

  describe "windows" do
    let(:games) { (1..25).map { |i| gv(i.even? ? 30 : 10, days_ago: i) } }

    it "takes the most recent N played games regardless of input order" do
      result = run(games.shuffle)
      expect(result.windows[:l5].n).to eq(5)
      expect(result.windows[:l10].n).to eq(10)
      expect(result.windows[:l20].n).to eq(20)
      expect(result.windows[:l5].hits).to eq(2) # days_ago 1..5 => odd values are 10, even are 30 => 2 evens
    end

    it "splits current and previous season" do
      mixed = [ gv(30, days_ago: 1), gv(30, days_ago: 2), gv(10, days_ago: 200, season: 2025), gv(30, days_ago: 201, season: 2025) ]
      result = run(mixed)
      expect(result.windows[:season]).to have_attributes(hits: 2, misses: 0)
      expect(result.windows[:prev_season]).to have_attributes(hits: 1, misses: 1)
    end

    it "H2H counts only this opponent, current and previous season" do
      h2h = [ gv(30, opponent: 7), gv(10, days_ago: 40, opponent: 7), gv(30, days_ago: 300, season: 2025, opponent: 7),
              gv(30, days_ago: 800, season: 2024, opponent: 7), gv(30, days_ago: 3, opponent: 9) ]
      w = run(h2h, opponent_id: 7).windows[:h2h]
      expect([ w.hits, w.misses ]).to eq([ 2, 1 ])
    end

    it "H2H is empty when the opponent is unknown" do
      expect(run([ gv(30) ], opponent_id: nil).windows[:h2h].n).to eq(0)
    end

    it "handles back-to-back dates and same-day ordering without losing games" do
      b2b = [ gv(30, days_ago: 1), gv(10, days_ago: 2), gv(30, days_ago: 3) ]
      expect(run(b2b).windows[:l5].n).to eq(3)
    end
  end

  describe "mean and median (L10 values)" do
    it "computes both, even and odd counts" do
      expect(run([ gv(10), gv(20, days_ago: 2), gv(30, days_ago: 3) ])).to have_attributes(mean: 20, median: 20)
      expect(run([ gv(10), gv(20, days_ago: 2), gv(30, days_ago: 3), gv(40, days_ago: 4) ])).to have_attributes(mean: 25, median: 25)
      expect(run([ gv(10), gv(20, days_ago: 2), gv(21, days_ago: 3), gv(100, days_ago: 4) ]).median).to eq(BigDecimal("20.5"))
    end

    it "is nil with no games" do
      expect(run([])).to have_attributes(mean: nil, median: nil)
    end
  end

  describe ".outcomes (for the segmented bar)" do
    it "returns oldest-first hit/miss/push for the last N played games" do
      games = [ gv(25, days_ago: 1), gv(20, days_ago: 2), gv(10, days_ago: 3), gv(0, days_ago: 4, minutes: 0) ]
      expect(described_class.outcomes(games: games, line: 20, side: "over")).to eq([ false, nil, true ])
      expect(described_class.outcomes(games: games, line: 20, side: "under")).to eq([ true, nil, false ])
    end

    it "limits to the requested count" do
      expect(described_class.outcomes(games: (1..30).map { |i| gv(30, days_ago: i) }, line: 20.5, side: "over", count: 5).size).to eq(5)
    end
  end

  it "rejects an invalid side" do
    expect { run([ gv(1) ], side: "middle") }.to raise_error(ArgumentError)
  end

  it "builds values from game logs using the stat catalog (PRA sums three stats)" do
    log = build(:player_game_log, points: 20, rebounds: 5, assists: 7)
    value = described_class.game_values([ log ], StatCatalog.for_market("player_pra")).first
    expect(value.value).to eq(32)
  end
end
