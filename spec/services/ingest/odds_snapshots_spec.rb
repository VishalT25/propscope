require "rails_helper"

RSpec.describe Ingest::OddsSnapshots do
  let!(:world) { build_world }

  def ingest(*quotes) = described_class.call(quotes: quotes.flatten, sport: world[:sport])

  def prop(price: -110, line: BigDecimal("24.5"), at: Time.utc(2026, 11, 9, 15), book: "draftkings", outcome: "over", name: "Dusan Markovic", **o)
    team = Dto::TeamRef.new(external_id: "BOSTON_CELTICS_NBA", name: nil, abbreviation: nil)
    quote(market_type: "player_points", line: line, american_odds: price, captured_at: at, bookmaker_key: book, outcome: outcome,
          player: Dto::PlayerRef.new(external_id: "DUSAN_MARKOVIC_1_NBA", name: name, team: team), **o)
  end

  it "resolves the game, creates the market and appends a snapshot with decimal odds" do
    expect(ingest(quote)).to have_attributes(inserted: 1, unresolved: 0)
    snap = OddsSnapshot.last
    expect(snap).to have_attributes(american_odds: -150, source_provider: "sports_game_odds", is_closing: false)
    expect(snap.decimal_odds).to eq(BigDecimal("1.6667"))
    expect(snap.market).to have_attributes(game: world[:game], market_type: "moneyline", line: nil)
  end

  it "is idempotent: ingesting the same quotes twice inserts nothing new" do
    batch = [ quote, quote(outcome: "away", american_odds: 130), prop ]
    ingest(batch)
    expect { ingest(batch) }.not_to change(OddsSnapshot, :count)
  end

  it "does not insert when a later quote has the same price and line" do
    ingest(prop(at: Time.utc(2026, 11, 9, 15)))
    result = ingest(prop(at: Time.utc(2026, 11, 9, 16)))
    expect(result).to have_attributes(inserted: 0, unchanged: 1)
  end

  it "inserts a new snapshot only when the price changes, keeping history" do
    ingest(prop(price: -110, at: Time.utc(2026, 11, 9, 15)))
    ingest(prop(price: -125, at: Time.utc(2026, 11, 9, 16)))
    ingest(prop(price: -125, at: Time.utc(2026, 11, 9, 17)))
    expect(OddsSnapshot.order(:captured_at).pluck(:american_odds)).to eq([ -110, -125 ])
  end

  it "treats a line move as a different market, so line movement stays queryable" do
    ingest(prop(line: BigDecimal("24.5")))
    ingest(prop(line: BigDecimal("25.5"), at: Time.utc(2026, 11, 9, 16)))
    expect(Market.where(market_type: "player_points").pluck(:line)).to contain_exactly(BigDecimal("24.5"), BigDecimal("25.5"))
  end

  it "ignores stale quotes older than the latest snapshot" do
    ingest(prop(price: -120, at: Time.utc(2026, 11, 9, 16)))
    result = ingest(prop(price: -105, at: Time.utc(2026, 11, 9, 15)))
    expect(result.stale).to eq(1)
    expect(OddsSnapshot.pluck(:american_odds)).to eq([ -120 ])
  end

  it "tracks over and under and each book independently" do
    ingest(prop(outcome: "over"), prop(outcome: "under", price: -110), prop(book: "fanduel", price: -105))
    expect(OddsSnapshot.count).to eq(3)
    expect(Bookmaker.pluck(:key)).to contain_exactly("draftkings", "fanduel")
  end

  it "records the source provider so the newer of two providers wins per book" do
    ingest(prop(price: -110, at: Time.utc(2026, 11, 9, 15), provider: "sports_game_odds"))
    ingest(prop(price: -115, at: Time.utc(2026, 11, 9, 16), provider: "other_provider"))
    expect(OddsSnapshot.order(:captured_at).pluck(:source_provider)).to eq(%w[sports_game_odds other_provider])
  end

  it "matches players with accents or suffixes stripped" do
    expect(ingest(prop(name: "Dusan Markovic"))).to have_attributes(inserted: 1)
    expect(ingest(prop(name: "Jaylen Brooks", line: BigDecimal("18.5"),
                       player: Dto::PlayerRef.new(external_id: "JB", name: "Jaylen Brooks",
                                                  team: Dto::TeamRef.new(external_id: "LOS_ANGELES_LAKERS_NBA", name: nil, abbreviation: nil))))).to have_attributes(inserted: 1)
  end

  it "skips (never guesses) unknown players and games, and records them" do
    stranger = prop(name: "Unmatched Rookie", player: Dto::PlayerRef.new(external_id: "UR", name: "Unmatched Rookie", team: Dto::TeamRef.new(external_id: "BOSTON_CELTICS_NBA", name: nil, abbreviation: nil)))
    elsewhere = quote(event_id: "EVT_X", starts_at: Time.utc(2026, 12, 25))
    result = ingest(stranger, elsewhere, quote)
    expect(result).to have_attributes(inserted: 1, unresolved: 2)
    expect(UnresolvedEntity.open.pluck(:external_type)).to contain_exactly("player", "game")
  end

  it "records an unmatched player once per run, not once per quote" do
    stranger = Dto::PlayerRef.new(external_id: "UR", name: "Unmatched Rookie", team: Dto::TeamRef.new(external_id: "BOSTON_CELTICS_NBA", name: nil, abbreviation: nil))
    ingest(%w[draftkings fanduel betmgm].map { |b| prop(book: b, player: stranger) })
    expect(UnresolvedEntity.where(external_type: "player").count).to eq(1)
  end

  describe "append-only guarantee" do
    it "refuses updates to anything but is_closing" do
      ingest(quote)
      snap = OddsSnapshot.last
      expect { snap.update!(american_odds: -200) }.to raise_error(ActiveRecord::ReadOnlyRecord, /append-only/)
      expect { snap.reload.update!(is_closing: true) }.not_to raise_error
    end
  end
end
