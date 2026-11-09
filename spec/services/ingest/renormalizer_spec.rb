require "rails_helper"

RSpec.describe Ingest::Renormalizer do
  let(:today) { Providers::FixtureTransport::ANCHOR }
  let(:provider) { Providers::Fixture.new(today: today) }

  it "rebuilds data from stored payloads without any API call or budget spend" do
    provider.fetch_teams(sport: "nba")
    provider.fetch_players(sport: "nba")
    expect(Team.count).to eq(0)

    expect(described_class.call(provider: "balldontlie", since: 1.hour.ago)).to eq(2)
    expect([ Team.count, Player.count ]).to eq([ 16, 96 ])
    expect(ApiUsage.count).to eq(0)
  end

  it "is idempotent" do
    provider.fetch_teams(sport: "nba")
    described_class.call(provider: "balldontlie", since: 1.hour.ago)
    expect { described_class.call(provider: "balldontlie", since: 1.hour.ago) }.not_to change(Team, :count)
  end

  it "only replays payloads since the cutoff" do
    provider.fetch_teams(sport: "nba")
    RawPayload.update_all(fetched_at: 3.days.ago)
    expect(described_class.call(provider: "balldontlie", since: 1.day.ago)).to eq(0)
  end

  it "re-normalizes odds with the original fetch time" do
    Ingest::SeedFixtures.call(today: today)
    OddsSnapshot.delete_all
    expect(described_class.call(provider: "sports_game_odds", since: 1.hour.ago)).to eq(1)
    expect(OddsSnapshot.count).to be > 3000
  end
end
