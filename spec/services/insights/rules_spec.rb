require "rails_helper"

RSpec.describe "Insights rules" do
  Tier = Struct.new(:tier)

  def gv(value, days_ago:, home: true, opponent: 1, minutes: 30)
    HitRateCalculator::GameValue.new(date: Date.new(2026, 11, 9) - days_ago, season: 2026, opponent_id: opponent, value: value, minutes: minutes, game_id: days_ago, home: home)
  end

  # newest first, like the engine builds it
  def series(*values, **o) = values.each_with_index.map { |v, i| gv(v, days_ago: i + 1, **o) }

  def ctx(values, side: "over", line: 20.5, home: true, tier: nil, ranks: {}, better: nil, edge: ->(_) { nil })
    market = build(:market, line: line, market_type: "player_points")
    market.player.first_name = "Alex"
    market.player.last_name = "Smith"
    Insights::Context.new(market: market, side: side, player: market.player, game: market.game, stat: StatCatalog.for_market("player_points"),
                          values: values, home: home, opponent_tier: tier, ranks: ranks, better_record: better, records_edge: edge)
  end

  describe Insights::Rules::HitStreak do
    it "reports consecutive overs with the average" do
      r = described_class.call(ctx(series(25, 30, 22, 28, 26, 10))).first
      expect(r.statement).to eq("Alex Smith has exceeded 20.5 points in 5 straight games (26.2 average).")
      expect(r.rule_key).to eq("hit_streak")
      expect(r.strength).to be > 50
    end

    it "needs 4 games, stops at a miss or a push, and is for the over only" do
      expect(described_class.call(ctx(series(25, 30, 22, 10)))).to be_empty
      expect(described_class.call(ctx(series(25, 30, 10, 22, 28, 26)))).to be_empty
      expect(described_class.call(ctx(series(25, 30, 20.5, 22, 28, 26)))).to be_empty # a push (exactly on the line) breaks the streak too
      expect(described_class.call(ctx(series(25, 30, 22, 28), side: "under"))).to be_empty
    end

    it "ranks a longer streak higher" do
      short = described_class.call(ctx(series(25, 30, 22, 28))).first
      long = described_class.call(ctx(series(*[ 25 ] * 12))).first
      expect(long.strength).to be > short.strength
    end
  end

  describe Insights::Rules::MissStreak do
    it "reports consecutive games under the line, for the under" do
      r = described_class.call(ctx(series(10, 12, 8, 15, 30), side: "under")).first
      expect(r.statement).to eq("Alex Smith has failed to exceed 20.5 points in 4 straight games.")
      expect(r.rule_key).to eq("miss_streak")
    end

    it "does nothing for the over or a short streak" do
      expect(described_class.call(ctx(series(10, 12, 8, 15)))).to be_empty
      expect(described_class.call(ctx(series(10, 12, 30), side: "under"))).to be_empty
    end
  end

  describe Insights::Rules::HomeRoadSplit do
    let(:values) { [ 25, 30, 22, 10, 28, 26, 24, 27 ].each_with_index.map { |v, i| gv(v, days_ago: i + 1, home: true) } + series(5, 6, 7, 8, 9, home: false).map { |g| g.with(home: false) } }

    it "uses only games at tonight's venue" do
      r = described_class.call(ctx(values, home: true)).first
      expect(r.statement).to eq("Alex Smith has gone over 20.5 points in 7 of the last 8 home games.")
      expect(described_class.call(ctx(values, home: false))).to be_empty # road games are all misses for the over
    end

    it "words the under side and the road venue" do
      road = (1..6).map { |i| gv(5, days_ago: i, home: false) }
      expect(described_class.call(ctx(road, side: "under", home: false)).first.statement).to eq("Alex Smith has stayed under 20.5 points in 6 of the last 6 road games.")
    end

    it "needs 5 decided games and an 80% rate" do
      expect(described_class.call(ctx((1..4).map { |i| gv(30, days_ago: i) }))).to be_empty
      expect(described_class.call(ctx([ 30, 30, 30, 30, 10, 10 ].each_with_index.map { |v, i| gv(v, days_ago: i + 1) }))).to be_empty
    end
  end

  describe Insights::Rules::VsDefenseTier do
    let(:ranks) { { 1 => Tier.new("favorable"), 2 => Tier.new("unfavorable"), 3 => Tier.new("neutral") } }

    it "compares against defences in tonight's tier" do
      values = (1..6).map { |i| gv(28, days_ago: i, opponent: 1) } + (7..10).map { |i| gv(5, days_ago: i, opponent: 2) }
      r = described_class.call(ctx(values, tier: "favorable", ranks: ranks)).first
      expect(r.statement).to eq("Alex Smith has gone over 20.5 points in 6 of 6 games against bottom-third defenses.")
      expect(described_class.call(ctx(values, tier: "unfavorable", ranks: ranks))).to be_empty
    end

    it "labels the toughest tier" do
      values = (1..5).map { |i| gv(5, days_ago: i, opponent: 2) }
      expect(described_class.call(ctx(values, side: "under", tier: "unfavorable", ranks: ranks)).first.statement).to include("top-third defenses")
    end

    it "does nothing for a neutral or unknown opponent" do
      values = (1..6).map { |i| gv(28, days_ago: i, opponent: 3) }
      expect(described_class.call(ctx(values, tier: "neutral", ranks: ranks))).to be_empty
      expect(described_class.call(ctx(values, tier: nil, ranks: ranks))).to be_empty
    end
  end

  describe Insights::Rules::RecordEdge do
    let(:values) { (1..8).map { |i| gv(i <= 6 ? 28 : 5, days_ago: i) } }
    let(:edge) { ->(g) { g.date >= Date.new(2026, 11, 2) ? true : false } } # first 7 games: better record

    it "compares games where the team had the same record edge as tonight" do
      r = described_class.call(ctx(values, better: true, edge: edge)).first
      expect(r.statement).to eq("Alex Smith has gone over 20.5 points in 6 of 7 games when the team had the better record.")
      expect(r.rule_key).to eq("record_edge")
    end

    it "is silent when records are unknown or the sample is thin" do
      expect(described_class.call(ctx(values, better: nil, edge: edge))).to be_empty
      expect(described_class.call(ctx(values.first(3), better: true, edge: edge))).to be_empty
    end
  end

  describe Insights::Strength do
    it "weights rate by sample size, caps at 100 and handles empty input" do
      expect(described_class.score(100, 5)).to be < described_class.score(100, 12)
      expect(described_class.score(100, 100)).to eq(100)
      expect(described_class.score(nil, 5)).to eq(0)
      expect(described_class.score(80, 0)).to eq(0)
      expect(described_class.score(90, 10)).to be > described_class.score(70, 10)
    end
  end
end

RSpec.describe Insights::Engine do
  seed_fixtures_once

  it "stores ranked insights for upcoming props from every kind of rule" do
    count = described_class.call
    expect(count).to be > 50
    expect(Insight.count).to eq(count)
    expect(Insight.pluck(:rule_key).uniq.size).to be >= 3
    expect(Insight.minimum(:strength)).to be >= Insights::Engine::MIN_STRENGTH
    expect(Insight.where(subject_type: "Player").count).to eq(count)
  end

  it "is idempotent: rerunning replaces rather than duplicates" do
    first = described_class.call
    expect(described_class.call).to eq(first)
    expect(Insight.count).to eq(first)
  end

  it "does not touch insights for games that have started" do
    described_class.call
    old = create(:game, starts_at: 2.days.ago)
    keep = Insight.create!(subject: create(:player), game: old, rule_key: "x", statement: "old", strength: 90, computed_at: 2.days.ago)
    described_class.call
    expect(Insight.exists?(keep.id)).to be(true)
  end

  it "only writes sides that a book is offering" do
    described_class.call
    Insight.includes(:market).limit(30).each do |i|
      expect(BestPrice.for(market_ids: [ i.market_id ])).to have_key([ i.market_id, i.side ])
    end
  end
end
