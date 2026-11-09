require "rails_helper"

RSpec.describe BestPrice do
  let(:market) { create(:market) }
  let(:dk) { create(:bookmaker, key: "dk", code: "DK") }
  let(:fd) { create(:bookmaker, key: "fd", code: "FD") }
  let(:mgm) { create(:bookmaker, key: "mgm", code: "MGM") }

  def snap(book, price, at = Time.current, outcome: "over", m: market)
    create(:odds_snapshot, market: m, bookmaker: book, outcome: outcome, american_odds: price, decimal_odds: OddsMath.american_to_decimal(price), captured_at: at)
  end

  it "picks the highest decimal price across books" do
    snap(dk, -115)
    snap(fd, -105)
    snap(mgm, -125)
    best = described_class.for(market_ids: [ market.id ])[[ market.id, "over" ]]
    expect(best).to have_attributes(american_odds: -105, books_count: 3)
    expect(best.bookmaker).to eq(fd)
    expect(best.decimal_odds).to eq(BigDecimal("1.9524"))
  end

  it "uses each book's latest snapshot only" do
    snap(dk, +120, 2.hours.ago)
    snap(dk, -110, 1.hour.ago)
    snap(fd, -105)
    best = described_class.for(market_ids: [ market.id ])[[ market.id, "over" ]]
    expect(best.bookmaker).to eq(fd)
    expect(best.books_count).to eq(2)
  end

  it "treats plus-money as better than minus-money" do
    snap(dk, +100)
    snap(fd, -102)
    expect(described_class.for(market_ids: [ market.id ])[[ market.id, "over" ]].american_odds).to eq(100)
  end

  it "only considers the enabled books" do
    snap(dk, +110)
    snap(fd, -105)
    best = described_class.for(market_ids: [ market.id ], bookmaker_ids: [ fd.id ])[[ market.id, "over" ]]
    expect(best).to have_attributes(american_odds: -105, books_count: 1)
  end

  it "returns nothing when no enabled book offers the market, or no books are enabled" do
    snap(dk, -110)
    expect(described_class.for(market_ids: [ market.id ], bookmaker_ids: [ fd.id ])).to be_empty
    expect(described_class.for(market_ids: [ market.id ], bookmaker_ids: [])).to be_empty
    expect(described_class.for(market_ids: [])).to be_empty
  end

  it "keeps over and under, and markets, separate" do
    other = create(:market)
    snap(dk, -110)
    snap(dk, -120, outcome: "under")
    snap(fd, +105, m: other)
    result = described_class.for(market_ids: [ market.id, other.id ])
    expect(result.keys).to contain_exactly([ market.id, "over" ], [ market.id, "under" ], [ other.id, "over" ])
  end

  it "breaks ties by the most recent snapshot" do
    snap(dk, -110, 2.hours.ago)
    snap(fd, -110, 1.hour.ago)
    expect(described_class.for(market_ids: [ market.id ])[[ market.id, "over" ]].bookmaker).to eq(fd)
  end
end
