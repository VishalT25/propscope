require "rails_helper"

RSpec.describe "Backfill" do
  let(:run) { BackfillRun.create!(seasons: 1) }
  let(:fixture) { Providers::Fixture.new(today: Date.current) }

  # The fixture provider with one call replaced, to make a provider misbehave in a specific way.
  def provider_with(method, &block)
    Class.new(SimpleDelegator) { define_method(method, &block) }.new(fixture)
  end

  describe Backfill::Estimate do
    let(:early_season) { Date.new(2026, 11, 11) } # a few weeks into the season
    let(:late_season) { Date.new(2027, 3, 1) }

    it "counts a full past season and only the days played of the current one" do
      expect(described_class.game_days(1, early_season)).to eq(20)
      expect(described_class.game_days(2, early_season)).to eq(233)
      expect(described_class.game_days(2, late_season)).to eq(343)
      expect(described_class.game_days(1, Date.new(2026, 6, 30))).to eq(213) # the season just ended
    end

    it "works out requests and minutes from the days and the plan's pace" do
      paid = described_class.call(seasons: 2, interval: 1.1, today: early_season)
      expect([ paid.game_days, paid.requests, paid.minutes ]).to eq([ 233, 771, 17 ])
      free = described_class.call(seasons: 1, interval: 12.5, today: early_season)
      expect([ free.requests, free.minutes ]).to eq([ 80, 20 ])
    end

    it "uses BallDontLie's paid-plan pace by default" do
      expect(described_class.call(seasons: 1, today: late_season).minutes).to be < 20
      expect(described_class.call(seasons: 2, today: late_season).minutes).to be < 30
    end
  end

  describe Backfill::Eta do
    let(:now) { Time.utc(2026, 11, 12, 4, 0, 0) }
    let(:started) { now - 60 }

    def run_at(phase, **attrs) = BackfillRun.create!(state: "running", phase: phase, seasons: 2, phase_started_at: started, **attrs)

    it "says which step it is, and counts requests and the rest of the time in the reference step" do
      run = run_at("reference", requests_done: 4, phase_requests_start: 0)
      eta = described_class.call(run, now: now, interval: 1.1)
      expect([ eta.step, eta.steps, eta.title, eta.unit ]).to eq([ 1, 4, "Teams, players and the schedule", "requests" ])
      expect([ eta.done, eta.total ]).to eq([ 4, 25 ])
      expect(eta.then_minutes).to be_positive
      expect(eta.seconds_left).to be > eta.then_minutes * 60 # this step, then the box scores, then the tail
    end

    it "uses the pace the step has actually managed once it has made enough requests" do
      slow = described_class.call(run_at("reference", requests_done: 10, phase_requests_start: 0), now: now, interval: 1.1) # 6 s a request
      fast = described_class.call(run_at("reference", requests_done: 30, phase_requests_start: 0), now: now, interval: 1.1) # past the expected count
      expect(slow.step_seconds).to eq(90)   # 15 requests left at 6 s each
      expect([ fast.total, fast.step_seconds ]).to eq([ 30, 2 ]) # never negative; always one more to go
    end

    it "is exact in the box-score step: days left, at the cost per day so far" do
      run = run_at("box_scores", total_days: 233, done_days: 20, requests_done: 80, phase_requests_start: 20) # 60 requests in 60 s, 3 a day
      eta = described_class.call(run, now: now, interval: 1.1)
      expect([ eta.step, eta.done, eta.total, eta.unit ]).to eq([ 2, 20, 233, "game days" ])
      expect(eta.step_seconds).to eq(639) # 213 days x 3 requests x 1 s
      expect(eta.seconds_left).to eq(639 + 60)
      expect(eta.finish_at).to eq(now + 699)
    end

    it "falls back to sensible defaults in a step's first moments" do
      run = run_at("box_scores", total_days: 100, done_days: 1, requests_done: 30, phase_requests_start: 28)
      eta = described_class.call(run, now: now, interval: 1.1)
      expect(eta.step_seconds).to eq((99 * Backfill::Estimate::REQUESTS_PER_DAY * 1.1 * 1.15).round)
    end

    it "has a short, fixed answer for the last two steps, and none of the counters" do
      ranks = described_class.call(run_at("ranks"), now: now)
      odds = described_class.call(run_at("odds"), now: now)
      expect([ ranks.step, ranks.total, ranks.seconds_left ]).to eq([ 3, nil, 42 ])
      expect([ odds.step, odds.seconds_left ]).to eq([ 4, 15 ])
    end
  end

  describe SetupsHelper, type: :helper do
    it "puts a number of seconds in words" do
      expect([ 10, 44 ].map { |s| helper.eta_phrase(s) }).to all(eq("less than a minute"))
      expect([ helper.eta_phrase(60), helper.eta_phrase(89) ]).to all(eq("about a minute"))
      expect([ helper.eta_phrase(150), helper.eta_phrase(11 * 60 + 20), helper.eta_phrase(3000) ]).to eq([ "about 3 minutes", "about 11 minutes", "about 50 minutes" ])
      expect([ helper.eta_phrase(3600), helper.eta_phrase(5400 + 60) ]).to eq([ "about 1 hour", "about 1 hour 31 min" ])
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

    it "counts the provider requests it makes, and when each step began, so the page can say how long is left" do
      described_class.call(run, provider: fixture)
      run.reload
      expect(run.requests_done).to be_positive
      expect(run.phase_started_at).to be_present
      expect(run.phase_requests_start).to be_positive # the later steps started after the earlier ones' requests
      expect(run.phase_requests).to be >= 0
    end

    it "does not count requests made by another thread" do
      described_class.call(run, provider: fixture)
      quiet = run.reload.requests_done
      PlayerGameLog.delete_all # so the second run has the same days to load

      noisy = provider_with(:fetch_teams) do |**kw|
        Thread.new { 5.times { ActiveSupport::Notifications.instrument("request.propscope", provider: "other", path: "/elsewhere") } }.join
        __getobj__.fetch_teams(**kw)
      end
      again = BackfillRun.create!(seasons: 1)
      described_class.call(again, provider: noisy)
      expect(again.reload.requests_done).to eq(quiet)
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
