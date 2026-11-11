require "rails_helper"

RSpec.describe "Backfill" do
  let(:run) { BackfillRun.create!(seasons: 1) }
  let(:fixture) { Providers::Fixture.new(today: Date.current) }

  # The fixture provider with one call replaced, to make a provider misbehave in a specific way.
  def provider_with(method, &block)
    Class.new(SimpleDelegator) { define_method(method, &block) }.new(fixture)
  end

  describe Backfill::Estimate do
    it "works out requests and minutes from the seasons and the plan's pace" do
      paid = described_class.call(seasons: 2, interval: 1.1)
      expect([ paid.game_days, paid.requests, paid.minutes ]).to eq([ 330, 1332, 25 ])
      free = described_class.call(seasons: 1, interval: 12.5)
      expect(free.minutes).to eq(140)
    end

    it "follows the plan chosen in Settings by default" do
      expect(described_class.call(seasons: 1).minutes).to be < 20
      Setting.set("balldontlie_plan", "free")
      expect(described_class.call(seasons: 1).minutes).to be > 100
    end
  end

  describe Backfill::Run do
    it "loads reference data and box scores, works out hit rates, fetches odds and reports each step" do
      lines = []
      described_class.call(run, provider: fixture, log: ->(m) { lines << m })
      run.reload
      expect([ run.state, run.phase, run.message ]).to eq([ "done", "odds", nil ])
      expect(run.total_days).to be_positive
      expect(run.done_days).to eq(run.total_days)
      expect([ run.started_at, run.finished_at, run.heartbeat_at ]).to all(be_present)
      expect(PlayerGameLog.count).to be_positive
      expect(PropHitRate.count).to be_positive
      expect(OddsSnapshot.count).to be_positive
      expect(lines).to include("Loading teams, players and the schedule", "Loading box scores", "Fetching today's odds")
    end

    it "is resumable: days that already have box scores are not fetched again" do
      described_class.call(run, provider: fixture)
      calls = 0
      counting = provider_with(:fetch_game_logs) { |**kw| calls += 1; __getobj__.fetch_game_logs(**kw) }
      again = BackfillRun.create!(seasons: 1)
      described_class.call(again, provider: counting)
      expect([ again.reload.state, again.total_days, calls ]).to eq([ "done", 0, 0 ])
    end

    it "stops when cancelled, keeps what it loaded, and says so" do
      served = 0
      provider = provider_with(:fetch_game_logs) do |**kw|
        served += 1
        BackfillRun.where(state: "running").update_all(cancel_requested: true) if served == 2
        __getobj__.fetch_game_logs(**kw)
      end
      described_class.call(run, provider: provider)
      run.reload
      expect([ run.state, run.done_days, served ]).to eq([ "cancelled", 2, 2 ])
      expect(run.message).to match(/Stopped.*kept/)
      expect(PlayerGameLog.count).to be_positive
    end

    it "pauses, with advice, when a provider's monthly budget runs out" do
      provider = provider_with(:fetch_game_logs) { |**| raise BudgetGuard::BudgetExceeded, "balldontlie budget exhausted (500/500 this month)" }
      described_class.call(run, provider: provider)
      expect([ run.reload.state, run.message ]).to match([ "paused", /budget exhausted.*Start it again/ ])
    end

    it "fails clearly when the provider turns the key down" do
      provider = provider_with(:fetch_teams) { |**| raise Faraday::UnauthorizedError.new("nope", { status: 401, headers: {}, body: "" }) }
      described_class.call(run, provider: provider)
      expect([ run.reload.state, run.message ]).to match([ "failed", /HTTP 401.*Check the key in Settings.*paid plan/ ])
    end

    it "fails clearly when there is no key" do
      provider = provider_with(:fetch_teams) { |**| raise ApiKeys::Missing, "No BallDontLie key yet. Add it in Settings, or set BALLDONTLIE_API_KEY." }
      described_class.call(run, provider: provider)
      expect([ run.reload.state, run.message ]).to match([ "failed", /No BallDontLie key/ ])
    end

    it "fails with a message, and never raises, on anything unexpected" do
      provider = provider_with(:fetch_players) { |**| raise "boom" }
      expect { described_class.call(run, provider: provider) }.not_to raise_error
      expect([ run.reload.state, run.message ]).to match([ "failed", /RuntimeError: boom.*start it again/ ])
    end
  end

  describe Backfill::Start do
    it "creates a run and queues it in the background" do
      expect { @started = described_class.call(seasons: 2) }.to have_enqueued_job(BackfillJob)
      expect([ @started.state, @started.seasons ]).to eq([ "queued", 2 ])
    end

    it "does not start a second run while one is going, but does once it has stalled" do
      first = described_class.call(seasons: 1)
      expect { expect(described_class.call(seasons: 2)).to eq(first) }.not_to have_enqueued_job(BackfillJob)

      first.update!(state: "running", heartbeat_at: 11.minutes.ago)
      expect(first).to be_stalled
      expect { expect(described_class.call(seasons: 1)).not_to eq(first) }.to have_enqueued_job(BackfillJob)
    end
  end

  describe BackfillJob do
    it "runs the service for its run" do
      allow(Backfill::Run).to receive(:call)
      described_class.perform_now(run.id)
      expect(Backfill::Run).to have_received(:call).with(run)
    end
  end

  describe BackfillRun do
    it "reports progress as a percentage once it knows the total" do
      expect(run.percent).to be_nil
      run.update!(total_days: 200, done_days: 50)
      expect(run.percent).to eq(25)
    end
  end
end
