require "rails_helper"

# Contract tests against a hand-trimmed sample of a REAL SportsGameOdds response (captured 2026-11-09, ~9KB,
# deep links removed). If the vendor changes its format, these fail first.
RSpec.describe "SportsGameOdds real response shape" do
  let(:body) { JSON.parse(Rails.root.join("spec/fixtures/providers/sports_game_odds/real_shape_sample.json").read) }
  let(:provider) { Providers::SportsGameOdds.new(transport: Providers::NullTransport.new, clock: -> { Time.utc(2026, 11, 9, 22) }) }
  let(:quotes) { provider.parse_events(body) }

  it "reads teams, abbreviations and start time" do
    q = quotes.first
    expect(q.home_team).to have_attributes(external_id: "ATLANTA_HAWKS_NBA", name: "Atlanta Hawks", abbreviation: "ATL")
    expect(q.away_team).to have_attributes(external_id: "LOS_ANGELES_LAKERS_NBA", abbreviation: "LAL")
    expect(q.starts_at).to eq(Time.utc(2026, 11, 10, 0, 0))
  end

  it "models only game-period moneyline, spread, total and the five prop stats" do
    expect(quotes.map(&:market_type).uniq).to match_array(%w[moneyline spread total player_points player_pra player_threes])
    expect(quotes.map(&:period).uniq).to eq([ "game" ])
  end

  it "reads string prices and lines into integers and BigDecimal, with the player and team" do
    over = quotes.find { |q| q.market_type == "player_points" && q.outcome == "over" && q.bookmaker_key == "fanduel" }
    expect(over).to have_attributes(american_odds: -102, line: BigDecimal("36.5"))
    expect(over.player).to have_attributes(external_id: "LUKA_DONCIC_1_NBA", name: "Luka Dončić")
    expect(over.player.team.external_id).to eq("LOS_ANGELES_LAKERS_NBA")
    expect(over.captured_at).to eq(Time.utc(2026, 11, 9, 21, 35, 18, 227_000))
  end

  it "reads spread lines from the per-book `spread` field" do
    spread = quotes.find { |q| q.market_type == "spread" && q.outcome == "home" }
    expect(spread.line).to be_a(BigDecimal)
    expect(spread.line.abs).to be < 30
  end

  it "skips bookmaker entries flagged unavailable" do
    dk_over = quotes.find { |q| q.market_type == "player_points" && q.outcome == "over" && q.bookmaker_key == "draftkings" }
    expect(dk_over).to be_nil
  end

  it "ignores unmodeled markets (first basket, blocks+steals, period lines)" do
    expect(quotes.map(&:market_type)).not_to include(nil)
  end

  describe "slimmed raw storage" do
    let(:slim) { provider.send(:storage_body, body) }

    it "replays to exactly the same quotes" do
      expect(provider.parse_events(slim)).to eq(quotes)
    end

    it "drops unmodeled markets and deep links" do
      odds = slim["data"].first["odds"]
      expect(odds.keys).to all(satisfy { |id| id.split("-", 5)[2] == "game" })
      expect(odds.keys).not_to include("firstBasket-AUSTIN_REAVES_1_NBA-game-yn-no")
      expect(slim.to_json).not_to include("deeplink")
    end

    it "is meaningfully smaller than what the parser was handed (synthetic full event)" do
      full = JSON.parse(Rails.root.join("spec/fixtures/providers/sports_game_odds/events.json").read)
      expect(provider.send(:storage_body, full).to_json.bytesize).to be < full.to_json.bytesize
    end
  end

  it "stores the slim payload, not the full response, when fetching" do
    transport = instance_double(Providers::HttpTransport, metered?: false, get: body.deep_dup)
    live = Providers::SportsGameOdds.new(transport: transport)
    live.fetch_odds(sport: "nba", event_ids: [ "x" ])
    expect(RawPayload.last.body["data"].first["odds"]).not_to have_key("points-home-1h-ml-home")
  end
end
