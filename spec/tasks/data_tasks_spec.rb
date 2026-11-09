require "rails_helper"
require "rake"

RSpec.describe "data rake tasks" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("data:seed_fixtures") }

  def run(task, env = {})
    Rake::Task[task].reenable
    stub_const("ENV", ENV.to_h.merge(env))
    Rake::Task[task].invoke
  end

  it "seeds from fixtures" do
    expect { run("data:seed_fixtures") }.to output(/Seeded: \d+ games/).to_stdout
    expect(Game.count).to be > 0
  end

  it "refuses live tasks unless LIVE_DATA=true" do
    expect { run("data:backfill_logs") }.to raise_error(SystemExit).and output(/LIVE_DATA/).to_stderr
    expect { run("data:capture_fixtures") }.to raise_error(SystemExit).and output(/LIVE_DATA/).to_stderr
  end

  it "re-normalizes stored payloads for a provider" do
    Providers::Fixture.new.fetch_teams(sport: "nba")
    expect { run("data:renormalize", "PROVIDER" => "balldontlie", "SINCE" => 1.hour.ago.iso8601) }.to output(/Re-normalized 1 payloads/).to_stdout
    expect(Team.count).to eq(16)
  end

  it "requires PROVIDER for renormalize" do
    expect { run("data:renormalize") }.to raise_error(SystemExit)
  end
end

RSpec.describe FixtureCapture do
  it "records live responses as fixture files through the live transports" do
    Dir.mktmpdir do |dir|
      stats = instance_double(Providers::BallDontLie, transport: instance_double(Providers::HttpTransport))
      odds = instance_double(Providers::SportsGameOdds, transport: instance_double(Providers::HttpTransport))
      allow(stats.transport).to receive(:get).and_return({ "data" => [] })
      allow(odds.transport).to receive(:get).and_return({ "success" => true, "data" => [] })
      described_class.call(root: Pathname.new(dir), odds: odds, stats: stats, today: Date.new(2026, 11, 9))
      expect(Dir.children(File.join(dir, "balldontlie"))).to contain_exactly("teams.json", "players_active.json", "games.json")
      expect(JSON.parse(File.read(File.join(dir, "sports_game_odds/events.json")))).to include("success" => true)
    end
  end
end
