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

  describe "line moves (a superseded line is not a live offer)" do
    let(:game) { market.game }
    let(:old_line) { market }
    let(:new_line) { create(:market, game: game, player: market.player, market_type: market.market_type, line: market.line + 1) }

    it "ignores a book's snapshot on the old line once it has posted the new line" do
      snap(dk, -110, 3.hours.ago, m: old_line)
      snap(dk, -115, 1.hour.ago, m: new_line)
      snap(fd, -105, 2.hours.ago, m: old_line) # fanduel never moved
      result = described_class.for(market_ids: [ old_line.id, new_line.id ])
      expect(result[[ old_line.id, "over" ]]).to have_attributes(american_odds: -105, books_count: 1)
      expect(result[[ new_line.id, "over" ]]).to have_attributes(american_odds: -115, books_count: 1)
    end

    it "drops the old line entirely when every book has moved" do
      snap(dk, -110, 3.hours.ago, m: old_line)
      snap(dk, -115, 1.hour.ago, m: new_line)
      expect(described_class.for(market_ids: [ old_line.id, new_line.id ]).keys).to eq([ [ new_line.id, "over" ] ])
    end

    it "still works when only the old line's market is asked about" do
      snap(dk, -110, 3.hours.ago, m: old_line)
      snap(dk, -115, 1.hour.ago, m: new_line)
      expect(described_class.for(market_ids: [ old_line.id ])).to be_empty
    end

    it "lets a book move back to the old line" do
      snap(dk, -110, 3.hours.ago, m: old_line)
      snap(dk, -115, 2.hours.ago, m: new_line)
      snap(dk, -120, 1.hour.ago, m: old_line)
      result = described_class.for(market_ids: [ old_line.id, new_line.id ])
      expect(result.keys).to eq([ [ old_line.id, "over" ] ])
      expect(result[[ old_line.id, "over" ]].american_odds).to eq(-120)
    end

    it "keeps alternate lines side by side" do
      alt = create(:market, game: game, player: market.player, market_type: market.market_type, line: market.line + 5, is_alternate: true)
      snap(dk, -110, 2.hours.ago, m: old_line)
      snap(dk, +250, 1.hour.ago, m: alt)
      expect(described_class.for(market_ids: [ old_line.id, alt.id ]).keys).to contain_exactly([ old_line.id, "over" ], [ alt.id, "over" ])
    end

    it "handles game-level markets with no player" do
      ml = create(:market, game: game, player: nil, market_type: "moneyline", line: nil)
      snap(dk, -150, 1.hour.ago, outcome: "over", m: ml)
      expect(described_class.for(market_ids: [ ml.id ]).keys).to eq([ [ ml.id, "over" ] ])
    end
  end
end
