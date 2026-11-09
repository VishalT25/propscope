require "rails_helper"

RSpec.describe Providers::BallDontLie do
  let(:today) { Providers::FixtureTransport::ANCHOR }
  let(:provider) { Providers::Fixture.new(today: today).stats }

  it "maps teams to DTOs" do
    team = provider.fetch_teams(sport: "nba").find { |t| t.abbreviation == "BOS" }
    expect(team).to have_attributes(provider: "balldontlie", name: "Boston Celtics", conference: "East", division: "Atlantic")
  end

  it "drops the defunct franchises the real /teams endpoint also returns (blank conference, reused abbreviations)" do
    body = { "data" => [
      { "id" => 30, "conference" => "West", "division" => "Southeast", "city" => "Washington", "name" => "Wizards", "full_name" => "Washington Wizards", "abbreviation" => "WAS" },
      { "id" => 42, "conference" => "    ", "division" => "    ", "city" => "Washington", "name" => "Capitols", "full_name" => "Washington Capitols", "abbreviation" => "WAS" },
      { "id" => 37, "conference" => nil, "division" => nil, "city" => "Chicago", "name" => "Stags", "full_name" => "Chicago Stags", "abbreviation" => "CHS" }
    ] }
    expect(provider.parse_teams(body).map(&:name)).to eq([ "Washington Wizards" ])
  end

  it "maps players with their team ref" do
    players = provider.fetch_players(sport: "nba")
    expect(players.size).to eq(96)
    expect(players.first.team).to be_a(Dto::TeamRef)
    expect(players.map(&:last_name)).to include("Marković")
  end

  it "maps today's scheduled games and past finals" do
    events = provider.fetch_events(sport: "nba", from: today - 3, to: today)
    today_games = events.select { |e| e.starts_at.in_time_zone(Game::SLATE_ZONE).to_date == today }
    expect(today_games.size).to eq(8)
    expect(today_games).to all(have_attributes(status: "scheduled", home_score: nil))
    final = events.find { |e| e.status == "final" }
    expect(final.home_score).to be_a(Integer)
    expect(final.season).to eq(2026)
  end

  it "maps box scores, derives opponent/home and treats blank minutes as DNP" do
    logs = provider.fetch_game_logs(sport: "nba", date: today - 1)
    expect(logs).not_to be_empty
    log = logs.first
    expect(log.opponent_team_external_id).not_to eq(log.team_external_id)
    expect(log.minutes).to be_a(BigDecimal)
    expect(logs.select { |l| l.minutes.zero? }).to all(have_attributes(points: 0))
    expect(logs.map(&:home).uniq).to contain_exactly(true, false)
  end

  describe "minute parsing" do
    def minutes(value)
      body = { "data" => [ { "min" => value, "pts" => 1, "player" => { "id" => 1, "first_name" => "A", "last_name" => "B" }, "team" => { "id" => 1 },
                             "game" => { "id" => 9, "date" => "2026-11-08", "home_team_id" => 1, "visitor_team_id" => 2 } } ] }
      provider.parse_game_logs(body).first.minutes
    end

    it { expect(minutes("34:30")).to eq(BigDecimal("34.5")) }
    it { expect(minutes("34")).to eq(34) }
    it { expect(minutes("")).to eq(0) }
    it { expect(minutes(nil)).to eq(0) }
    it { expect(minutes("00")).to eq(0) }
  end

  it "paginates with next_cursor until it is absent" do
    pages = [
      { "data" => [ { "id" => 1, "abbreviation" => "AAA", "full_name" => "A A" } ], "meta" => { "next_cursor" => 7 } },
      { "data" => [ { "id" => 2, "abbreviation" => "BBB", "full_name" => "B B" } ], "meta" => {} }
    ]
    transport = instance_double(Providers::FixtureTransport, metered?: false)
    allow(transport).to receive(:get).and_return(*pages)
    real = described_class.new(transport: transport)
    expect(real.send(:paginate, "/players/active").size).to eq(2)
    expect(transport).to have_received(:get).with("/players/active", hash_including("cursor" => 7))
  end

  it "stores a raw payload for every request before parsing" do
    expect { provider.fetch_teams(sport: "nba") }.to change(RawPayload, :count).by(1)
    raw = RawPayload.last
    expect([ raw.provider, raw.endpoint, raw.status ]).to eq([ "balldontlie", "/teams", 200 ])
    expect(raw.body_sha256).to match(/\A\h{64}\z/)
  end

  it "does not support odds" do
    expect { provider.fetch_odds(sport: "nba") }.to raise_error(NotImplementedError)
  end
end
