require "rails_helper"

RSpec.describe "Setup" do
  let(:ok) { Providers::KeyCheck::Result.new(true, nil, "Key works.") }
  let(:ok_scores) { Providers::KeyCheck::Result.new(true, true, "Key works, and your plan includes box scores.") }
  let(:no_scores) { Providers::KeyCheck::Result.new(true, false, "Key works, but your plan has no box scores.") }

  before { allow(Rails.configuration.x).to receive_messages(single_user: true, require_setup: true) }

  def stub_checks(sgo: ok, bdl: ok_scores)
    allow(Providers::KeyCheck).to receive(:call).with("sports_game_odds").and_return(sgo)
    allow(Providers::KeyCheck).to receive(:call).with("balldontlie").and_return(bdl)
  end

  def keys_ready!
    stub_checks
    Setup.verify("sports_game_odds")
    Setup.verify("balldontlie")
    ApiKeys.set("sports_game_odds", "sgo-key-1111")
    ApiKeys.set("balldontlie", "bdl-key-2222")
  end

  describe "the first-run gate" do
    it "sends a fresh install to setup from every page, but never setup itself or the health check" do
      get "/nba/props"
      expect(response).to redirect_to(setup_path)
      get "/"
      expect(response).to redirect_to(setup_path)
      get "/setup"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Use my own data", "Use sample data")
      get "/up"
      expect(response).to have_http_status(:ok)
    end

    it "shows a bare header while setup is required: nothing to navigate to yet" do
      get "/setup"
      expect(response.body).not_to include("Insights", "My picks")
    end

    it "leaves an install that already has data alone, and does not gate when accounts are on" do
      create(:game)
      get "/nba/props"
      expect(response).to have_http_status(:ok)
      Game.delete_all
      allow(Rails.configuration.x).to receive(:single_user).and_return(false)
      get "/nba/props"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "choosing" do
    it "loads sample data and opens the app" do
      allow(Ingest::SeedFixtures).to receive(:call) { create(:game) }
      post "/setup/choose", params: { mode: "sample" }
      expect(response).to redirect_to(root_path)
      expect(Setup.mode).to eq("sample")
      get "/nba/props"
      expect(response).to have_http_status(:ok)
    end

    it "returns you to the page you came from after loading sample data, never to another site" do
      allow(Ingest::SeedFixtures).to receive(:call) { create(:game) }
      post "/setup/choose", params: { mode: "sample", back: "/nba/props" }
      expect(response).to redirect_to("/nba/props")
      post "/setup/choose", params: { mode: "sample", back: "https://evil.example/phish" }
      expect(response).to redirect_to(root_path)
    end

    it "takes you to the keys for your own data, and back" do
      post "/setup/choose", params: { mode: "live" }
      follow_redirect!
      expect(response.body).to include("SportsGameOdds", "BallDontLie", "Save and test keys", "Not tested yet")
      expect(LiveData.enabled?).to be(false) # nothing is called until the history load starts
      post "/setup/choose", params: { mode: "back" }
      follow_redirect!
      expect(response.body).to include("Use my own data")
    end
  end

  describe "keys" do
    before { Setup.choose_live }

    it "saves and tests both keys, then moves on to the history step" do
      stub_checks
      patch "/setup/keys", params: { keys: { sports_game_odds: " sgo-key-1111 ", balldontlie: "bdl-key-2222" } }
      expect(response).to redirect_to(setup_path)
      expect(flash[:notice]).to match(/Both keys work/)
      expect([ ApiKeys.get("sports_game_odds"), ApiKeys.get("balldontlie") ]).to eq([ "sgo-key-1111", "bdl-key-2222" ])
      follow_redirect!
      expect(response.body).to include("How much history?")
      expect(response.body).to match(/about \d+ minutes, roughly [\d,]+ requests/)
    end

    it "never shows a saved key again, only its last four characters" do
      stub_checks
      patch "/setup/keys", params: { keys: { sports_game_odds: "sgo-key-1111", balldontlie: "bdl-super-secret-2222" } }
      get "/setup", params: { step: "keys" }
      expect(response.body).not_to include("bdl-super-secret-2222", "sgo-key-1111")
      expect(response.body).to include("••••2222", "••••1111")
      get "/settings"
      expect(response.body).not_to include("bdl-super-secret-2222")
    end

    it "explains a key that does not work, and a plan without box scores" do
      stub_checks(sgo: Providers::KeyCheck::Result.new(false, nil, "SportsGameOdds did not accept that key (HTTP 401)."), bdl: no_scores)
      patch "/setup/keys", params: { keys: { sports_game_odds: "bad", balldontlie: "free" } }
      expect(response).to redirect_to(setup_path(step: "keys"))
      expect(flash[:alert]).to include("SportsGameOdds did not accept that key", "BallDontLie: Key works, but your plan has no box scores")
      expect(Setup.keys_ready?).to be(false)
      get "/setup", params: { step: "keys" }
      expect(response.body).to include("Works, but no box scores")
    end

    it "asks for a key that is missing, and keeps one that is already saved when its box is left blank" do
      ApiKeys.set("sports_game_odds", "kept-key")
      stub_checks
      patch "/setup/keys", params: { keys: { sports_game_odds: "", balldontlie: "" } }
      expect(flash[:alert]).to eq("Add your BallDontLie key.")
      expect(ApiKeys.get("sports_game_odds")).to eq("kept-key")
    end

    it "lets an environment key stand in for typing one" do
      stub_const("ENV", ENV.to_h.merge("SPORTSGAMEODDS_API_KEY" => "from-env", "BALLDONTLIE_API_KEY" => "from-env-2"))
      stub_checks
      patch "/setup/keys", params: { keys: { sports_game_odds: "", balldontlie: "" } }
      expect(flash[:notice]).to match(/Both keys work/)
      get "/setup", params: { step: "keys" }
      expect(response.body).to include("environment variable")
    end
  end

  describe "loading history" do
    it "will not start before both keys have been tested" do
      post "/setup/backfill", params: { seasons: 2 }
      expect(response).to redirect_to(setup_path(step: "keys"))
      expect(BackfillRun.count).to eq(0)
    end

    it "turns live data on, queues the load in the background, and shows progress" do
      keys_ready!
      expect { post "/setup/backfill", params: { seasons: 2 } }.to have_enqueued_job(BackfillJob)
      expect([ Setup.mode, LiveData.enabled?, BackfillRun.last.seasons ]).to eq([ "live", true, 2 ])
      follow_redirect!
      expect(response.body).to include("Waiting to start", 'data-controller="poll"')
    end

    it "keeps the number of seasons sensible, and starts only one run at a time" do
      keys_ready!
      post "/setup/backfill", params: { seasons: 99 }
      expect { post "/setup/backfill", params: { seasons: 1 } }.not_to have_enqueued_job(BackfillJob)
      expect([ BackfillRun.count, BackfillRun.last.seasons ]).to eq([ 1, 3 ])
    end

    it "stops a run that is going when asked" do
      keys_ready!
      run = BackfillRun.create!(state: "running", heartbeat_at: Time.current)
      post "/setup/cancel"
      expect(run.reload.cancel_requested).to be(true)
    end

    it "shows each state of the progress panel, and polls only while it is going" do
      keys_ready!
      Setup.go_live
      run = BackfillRun.create!(state: "running", phase: "box_scores", total_days: 200, done_days: 50, heartbeat_at: Time.current)
      get "/setup/progress"
      expect(response.body).to include("Box scores", "step 2 of 4", "50 of 200 game days (25%)", 'data-controller="poll"', "Stop", "done around")
      expect(response.body).to match(/(less than a minute|about [\d a-z]+) left/i)

      run.update!(state: "paused", message: "balldontlie budget exhausted (500/500 this month). Start it again next month.")
      get "/setup/progress"
      expect(response.body).to include("Paused", "budget exhausted", "50 of 200 game days were loaded")
      expect(response.body).not_to include("data-controller=\"poll\"")

      run.update!(state: "running", heartbeat_at: 20.minutes.ago)
      get "/setup/progress"
      expect(response.body).to include("stopped reporting", "start it again")

      run.update!(state: "done", message: nil)
      get "/setup/progress"
      expect(response.body).to include("All set", "Open Propscope")
    end

    it "explains the reference step: how many requests, why it cannot be faster, and what comes next" do
      keys_ready!
      Setup.go_live
      BackfillRun.create!(state: "running", phase: "reference", seasons: 2, requests_done: 10, phase_requests_start: 0, phase_started_at: 20.seconds.ago, heartbeat_at: Time.current)
      get "/setup/progress"
      expect(response.body).to include("Teams, players and the schedule", "step 1 of 4", "request 10 of about 25", "cannot go faster", "Then come the box scores, about")
    end

    it "says it is waiting before the first step has begun" do
      keys_ready!
      Setup.go_live
      BackfillRun.create!(state: "queued")
      get "/setup/progress"
      expect(response.body).to include("Waiting to start")
      expect(response.body).not_to include("left")
    end

    it "gates the app until the history is loaded, then opens it" do
      keys_ready!
      post "/setup/backfill", params: { seasons: 1 }
      get "/nba/props"
      expect(response).to redirect_to(setup_path)
      BackfillRun.last.update!(state: "done")
      Setup.finish_live
      get "/nba/props"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "refreshing odds" do
    it "queues a fetch when live data is on, and says so when it is off" do
      Setting.set("data_mode", "sample")
      post "/setup/refresh_odds"
      expect(flash[:alert]).to match(/Live data is off/)
      Setting.set("data_mode", "live")
      expect { post "/setup/refresh_odds" }.to have_enqueued_job(SnapshotOddsJob).with("morning")
    end
  end

  describe "the Data section in Settings" do
    it "describes sample data, and offers your own" do
      Setting.set("data_mode", "sample")
      get "/settings"
      expect(response.body).to include("Sample data", "made up", "Use my own data")
    end

    it "shows live keys by their last four characters, the quota used, and the actions" do
      keys_ready!
      Setting.set("data_mode", "live")
      BackfillRun.create!(state: "done", finished_at: Time.current) # history loaded, so setup is complete
      ApiUsage.create!(provider: "sports_game_odds", period: ApiUsage.period_for(Time.current), units_used: 125, units_limit: 2500)
      get "/settings"
      expect(response.body).to include("Live data", "••••1111", "••••2222", "saved in the app", "125 of 2,500 used this month", "Refresh odds now", "Switch to sample data")
      expect(response.body).not_to include("sgo-key-1111", "bdl-key-2222")
    end
  end

  describe "who may change it" do
    it "turns an ordinary user away when accounts are on" do
      allow(Rails.configuration.x).to receive(:single_user).and_return(false)
      user = create(:user)
      post session_path, params: { email_address: user.email_address, password: "password123" }
      get "/setup"
      expect(response).to redirect_to(root_path)
      patch "/setup/keys", params: { keys: { balldontlie: "x" } }
      expect(ApiKeys.present?("balldontlie")).to be(false)
    end
  end
end
