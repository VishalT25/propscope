require "rails_helper"

RSpec.describe Ingest::GameLogs do
  let(:today) { Providers::FixtureTransport::ANCHOR }
  let(:provider) { Providers::Fixture.new(today: today) }
  let(:logs) { provider.fetch_game_logs(sport: "nba", date: today - 1) }

  before do
    Ingest::ReferenceData.call(teams: provider.fetch_teams(sport: "nba"), players: provider.fetch_players(sport: "nba"))
    Ingest::ReferenceData.call(events: provider.fetch_events(sport: "nba", from: today - 45, to: today))
  end

  it "stores one row per player-game with opponent, home flag and season" do
    result = described_class.call(logs: logs)
    expect(result.upserted).to eq(logs.size)
    log = PlayerGameLog.first
    expect(log.opponent_team).not_to eq(log.team)
    expect(log.season).to eq(2026)
    expect(log.game_date).to eq(today - 1)
  end

  it "is idempotent" do
    described_class.call(logs: logs)
    expect { described_class.call(logs: logs) }.not_to change(PlayerGameLog, :count)
  end

  it "overwrites a row when the provider corrects a stat" do
    described_class.call(logs: logs)
    fixed = logs.first.with(points: 99)
    described_class.call(logs: [ fixed ])
    expect(PlayerGameLog.where(points: 99).count).to eq(1)
  end

  it "keeps DNPs as zero-minute rows that the played scope excludes" do
    dnp = logs.first.with(minutes: BigDecimal("0"), points: 0, rebounds: 0, assists: 0)
    described_class.call(logs: [ dnp, logs.second ])
    row = PlayerGameLog.find_by(minutes: 0)
    expect(row).to be_dnp
    expect(PlayerGameLog.played.pluck(:id)).not_to include(row.id)
    expect(PlayerGameLog.played.count).to eq(1)
  end

  it "skips rows for players or games it does not know" do
    stranger = logs.first.with(player_external_id: "9999999")
    result = described_class.call(logs: [ stranger ])
    expect(result).to have_attributes(upserted: 0, skipped: 1)
  end

  it "returns zero for empty input" do
    expect(described_class.call(logs: [])).to have_attributes(upserted: 0, skipped: 0)
  end
end
