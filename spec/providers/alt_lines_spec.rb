require "rails_helper"

# Alternate lines and betslip deeplinks, against a trimmed copy of a REAL SportsGameOdds response (includeAltLines=true).
RSpec.describe "SportsGameOdds alternate lines and deeplinks" do
  let(:body) { JSON.parse(Rails.root.join("spec/fixtures/providers/sports_game_odds/real_shape_alt_lines_sample.json").read) }
  let(:provider) { Providers::SportsGameOdds.new(transport: Providers::NullTransport.new, clock: -> { Time.utc(2026, 11, 10, 20) }) }
  let(:quotes) { provider.parse_events(body) }
  let(:alts) { quotes.select(&:is_alternate) }
  let(:mains) { quotes.reject(&:is_alternate) }

  it "keeps the main lines and adds sensible alternates, flagged" do
    expect(mains).not_to be_empty
    expect(alts).not_to be_empty
    expect(alts.map(&:market_type).uniq).to include("total")
  end

  it "drops unavailable, junk-priced and far-away alternates, and never repeats the main line" do
    raw = body["data"].first["odds"].values.flat_map { |o| o["byBookmaker"].values.flat_map { |b| b["altLines"] } }
    expect(alts.size).to be < raw.size / 2 # the raw list is mostly noise (-10000 and the like)
    expect(alts.map(&:american_odds)).to all(be_between(-1000, 2000))
    main_lines = mains.group_by { |q| [ q.market_type, q.player&.external_id, q.bookmaker_key, q.outcome ] }.transform_values { |qs| qs.first.line }
    alts.each do |a|
      main = main_lines.fetch([ a.market_type, a.player&.external_id, a.bookmaker_key, a.outcome ])
      expect(a.line).not_to eq(main)
      expect((a.line - main).abs).to be <= 10
    end
  end

  it "carries the book's own betslip link on the main quote" do
    expect(mains.filter_map(&:deeplink)).not_to be_empty
    expect(mains.filter_map(&:deeplink)).to all(start_with("https://"))
    expect(alts.map(&:deeplink).uniq).to eq([ nil ])
  end

  it "stores a slim payload that replays to exactly the same quotes, alternates and links included" do
    slim = provider.send(:storage_body, body)
    expect(provider.parse_events(slim)).to eq(quotes)
    expect(slim.to_json.bytesize).to be < body.to_json.bytesize
  end

  it "asks for alternate lines unless INCLUDE_ALT_LINES=false (same cost either way)" do
    transport = instance_double(Providers::HttpTransport, metered?: false, get: { "data" => [] })
    expect(transport).to receive(:get).with("/events", hash_including("includeAltLines" => "true")).and_return({ "data" => [] })
    Providers::SportsGameOdds.new(transport: transport).fetch_odds(sport: "nba", event_ids: [ "x" ])
    stub_const("ENV", ENV.to_h.merge("INCLUDE_ALT_LINES" => "false"))
    transport2 = instance_double(Providers::HttpTransport, metered?: false)
    expect(transport2).to receive(:get).with("/events", hash_not_including("includeAltLines")).and_return({ "data" => [] })
    Providers::SportsGameOdds.new(transport: transport2).fetch_odds(sport: "nba", event_ids: [ "x" ])
  end
end

RSpec.describe "Alternate lines and deeplinks in the app" do
  let!(:world) { build_world }
  let(:game) { world[:game] }
  let(:player) { world[:p1] }
  let(:book) { create(:bookmaker, key: "fd", code: "FD") }

  def ingest(*quotes) = Ingest::OddsSnapshots.call(quotes: quotes.flatten, sport: world[:sport])

  def prop(line:, price: -110, alt: false, deeplink: nil, at: Time.utc(2026, 11, 9, 15), outcome: "over")
    team = Dto::TeamRef.new(external_id: "BOSTON_CELTICS_NBA", name: nil, abbreviation: nil)
    quote(market_type: "player_points", line: BigDecimal(line.to_s), american_odds: price, captured_at: at, starts_at: game.starts_at, bookmaker_key: "fd", outcome: outcome, is_alternate: alt, deeplink: deeplink,
          player: Dto::PlayerRef.new(external_id: "DUSAN_MARKOVIC_1_NBA", name: "Dusan Markovic", team: team))
  end

  it "stores alternates as their own markets next to the main line, and keeps their deeplinks off" do
    ingest(prop(line: 24.5, deeplink: "https://book.test/main"), prop(line: 27.5, price: 150, alt: true), prop(line: 21.5, price: -160, alt: true))
    expect(Market.where(player: player).order(:line).pluck(:line, :is_alternate)).to eq([ [ 21.5, true ], [ 24.5, false ], [ 27.5, true ] ].map { |l, a| [ BigDecimal(l.to_s), a ] })
    expect(OddsSnapshot.where.not(deeplink: nil).pluck(:deeplink)).to eq([ "https://book.test/main" ])
  end

  it "fills in a missing deeplink on an unchanged price without inserting a new snapshot" do
    ingest(prop(line: 24.5))
    expect(OddsSnapshot.pluck(:deeplink)).to eq([ nil ])
    result = ingest(prop(line: 24.5, deeplink: "https://book.test/slip", at: Time.utc(2026, 11, 9, 16)))
    expect(result).to have_attributes(inserted: 0, unchanged: 1)
    expect(OddsSnapshot.pluck(:deeplink)).to eq([ "https://book.test/slip" ])
    expect(OddsSnapshot.count).to eq(1)
  end

  it "still refuses to rewrite a price (only metadata is editable)" do
    ingest(prop(line: 24.5))
    expect { OddsSnapshot.last.update!(american_odds: -200) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { OddsSnapshot.last.reload.update!(deeplink: "https://x.test") }.not_to raise_error
  end

  it "never lets an alternate line define a closing line" do
    ingest(prop(line: 24.5), prop(line: 21.5, price: -160, alt: true), prop(line: 21.5, price: -160, alt: true, at: Time.utc(2026, 11, 9, 15, 1)))
    OddsSnapshot.update_all(is_closing: true)
    expect(ClosingLines.call(player_ids: [ player.id ]).values).to eq([ BigDecimal("24.5") ])
  end

  it "keeps alternate markets out of EV and arbitrage pairs, and out of the explorer unless asked" do
    game.update!(starts_at: 5.hours.from_now)
    ingest(prop(line: 24.5), prop(line: 24.5, outcome: "under"), prop(line: 27.5, price: 150, alt: true), prop(line: 27.5, price: -180, alt: true, outcome: "under"))
    expect(TwoWayMarkets.call.map { |p| p.left.market.is_alternate }.uniq).to eq([ false ])
    HitRates::Precompute.call
    plain = PropsQuery.call(filters: PropsQuery::Filters.from_params({}), paginate: false).rows.map { |r| r.market.line }.uniq
    with_alt = PropsQuery.call(filters: PropsQuery::Filters.from_params("alt" => "1"), paginate: false).rows.map { |r| r.market.line }.uniq
    expect(plain).to eq([ BigDecimal("24.5") ])
    expect(with_alt).to match_array([ BigDecimal("24.5"), BigDecimal("27.5") ])
  end
end
