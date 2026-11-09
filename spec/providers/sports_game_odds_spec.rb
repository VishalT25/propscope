require "rails_helper"

RSpec.describe Providers::SportsGameOdds do
  let(:provider) { Providers::Fixture.new(today: Providers::FixtureTransport::ANCHOR).odds }
  let(:quotes) { provider.fetch_odds(sport: "nba", from: Time.utc(2026, 11, 9), to: Time.utc(2026, 11, 11)) }

  it "returns only DTOs" do
    expect(quotes).to all(be_a(Dto::OddsQuote))
  end

  it "parses game lines with prices as integers and lines as BigDecimal" do
    ml = quotes.find { |q| q.market_type == "moneyline" }
    expect(ml).to have_attributes(period: "game", line: nil, outcome: be_in(%w[home away]))
    expect(ml.american_odds).to be_an(Integer)
    spread = quotes.find { |q| q.market_type == "spread" }
    expect(spread.line).to be_a(BigDecimal)
    total = quotes.find { |q| q.market_type == "total" }
    expect(total.line).to be > 200
  end

  it "parses player props with a player ref and the right market types" do
    props = quotes.select(&:player)
    expect(props.map(&:market_type).uniq).to match_array(%w[player_points player_rebounds player_assists player_threes player_pra])
    prop = props.first
    expect(prop.player.external_id).to match(/_1_NBA\z/)
    expect(prop.player.team.external_id).to end_with("_NBA")
    expect(prop.line).to be_a(BigDecimal)
  end

  it "ignores period markets and team totals (out of scope)" do
    expect(quotes.map(&:period).uniq).to eq([ "game" ])
    expect(quotes.none? { |q| q.market_type.nil? }).to be(true)
  end

  it "covers the five fixture books and every game on the slate" do
    expect(quotes.map(&:bookmaker_key).uniq).to match_array(%w[draftkings fanduel betmgm caesars espnbet])
    expect(quotes.map(&:event_id).uniq.size).to eq(8)
  end

  it "skips unavailable prices and unparseable odds" do
    body = { "data" => [ { "eventID" => "E", "teams" => { "home" => { "teamID" => "H", "names" => { "short" => "H" } }, "away" => { "teamID" => "A", "names" => { "short" => "A" } } },
                           "status" => { "startsAt" => "2026-11-10T00:00:00.000Z" },
                           "odds" => { "points-home-game-ml-home" => { "byBookmaker" => { "a" => { "odds" => "-110", "available" => false },
                                                                                          "b" => { "odds" => "n/a", "available" => true },
                                                                                          "c" => { "odds" => "+120", "available" => true } } } } } ] }
    parsed = provider.parse_events(body)
    expect(parsed.map(&:bookmaker_key)).to eq([ "c" ])
    expect(parsed.first.american_odds).to eq(120)
  end

  it "uses the bookmaker's lastUpdatedAt when present, else the fetch time" do
    body = { "data" => [ { "eventID" => "E", "teams" => {}, "status" => { "startsAt" => "2026-11-10T00:00:00Z" },
                           "odds" => { "points-home-game-ml-home" => { "byBookmaker" => { "a" => { "odds" => "-110", "lastUpdatedAt" => "2026-11-09T14:00:00Z" },
                                                                                          "b" => { "odds" => "-120" } } } } } ] }
    a, b = provider.parse_events(body)
    expect(a.captured_at).to eq(Time.utc(2026, 11, 9, 14))
    expect(b.captured_at).to be_within(5.seconds).of(Time.current)
  end

  describe "cost accounting" do
    it "is one object per event, whatever the markets or books" do
      expect(provider.cost_of(:odds, 10)).to eq(10)
    end

    it "reserves budget for an id-based call by id count" do
      spent = []
      allow(BudgetGuard).to receive(:spend!) { |_, units, &blk| spent << units; blk.call }
      transport = instance_double(Providers::HttpTransport, metered?: true, get: { "data" => [] })
      described_class.new(transport: transport).fetch_odds(sport: "nba", event_ids: %w[a b c])
      expect(spent).to eq([ 3 ])
    end

    it "does not call the API when the budget is exhausted" do
      transport = instance_double(Providers::HttpTransport, metered?: true)
      allow(transport).to receive(:get)
      ApiUsage.create!(provider: "sports_game_odds", period: ApiUsage.period_for, units_used: 2500, units_limit: 2500)
      expect { described_class.new(transport: transport).fetch_odds(sport: "nba", event_ids: %w[a]) }.to raise_error(BudgetGuard::BudgetExceeded)
      expect(transport).not_to have_received(:get)
    end
  end

  it "replays a stored payload into the same quotes (renormalize)" do
    quotes # fetch, which stores the raw payload
    raw = RawPayload.find_by(provider: "sports_game_odds")
    kind, replayed = provider.replay(raw)
    expect(kind).to eq(:odds)
    expect(replayed.size).to eq(quotes.size)
  end
end
