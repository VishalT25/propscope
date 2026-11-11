require "rails_helper"

RSpec.describe "Setup" do
  def result(ok: true, box_scores: nil, message: "msg") = Providers::KeyCheck::Result.new(ok, box_scores, message)
  def checker(**by_provider) = Class.new { define_singleton_method(:call) { |provider| by_provider.fetch(provider.to_sym) } }

  describe Providers::KeyCheck do
    # A transport that answers from a table of path => response (or exception).
    def transport(responses)
      Class.new do
        attr_reader :calls

        define_method(:initialize) { @calls = [] }
        define_method(:get) do |path, params = {}|
          @calls << [ path, params ]
          r = responses.fetch(path)
          raise r if r.is_a?(Exception)

          r
        end
      end.new
    end

    def denied(status = 403) = Faraday::ForbiddenError.new("no", { status: status, headers: {}, body: "" })

    it "passes a SportsGameOdds key with one small request, and records the cost" do
      t = transport("/events" => { "data" => [] })
      r = described_class.call("sports_game_odds", transport: t)
      expect([ r.ok, r.box_scores, r.message ]).to eq([ true, nil, "Key works." ])
      expect(t.calls).to eq([ [ "/events", { "leagueID" => "NBA", "limit" => 1 } ] ])
      expect(BudgetGuard.report("sports_game_odds").used).to eq(1)
    end

    it "passes a BallDontLie key that includes box scores" do
      r = described_class.call("balldontlie", transport: transport("/teams" => {}, "/stats" => {}))
      expect([ r.ok, r.box_scores, r.message ]).to match([ true, true, /includes box scores/ ])
    end

    it "tells a free-plan BallDontLie key apart: it works, but has no box scores" do
      r = described_class.call("balldontlie", transport: transport("/teams" => {}, "/stats" => denied(401)))
      expect([ r.ok, r.box_scores, r.message ]).to match([ true, false, /no box scores.*paid \(ALL-STAR\) plan/ ])
    end

    it "explains a key the provider rejects, an unreachable provider, rate limiting and a missing key" do
      rejected = described_class.call("balldontlie", transport: transport("/teams" => denied(401)))
      expect([ rejected.ok, rejected.message ]).to match([ false, /BallDontLie did not accept that key \(HTTP 401\)/ ])

      offline = described_class.call("sports_game_odds", transport: transport("/events" => Faraday::ConnectionFailed.new("down")))
      expect(offline.message).to match(/Could not reach SportsGameOdds/)

      limited = described_class.call("sports_game_odds", transport: transport("/events" => Faraday::TooManyRequestsError.new("slow", { status: 429, headers: {}, body: "" })))
      expect(limited.message).to match(/too many requests/)

      missing = described_class.call("balldontlie", transport: transport("/teams" => ApiKeys::Missing.new("none")))
      expect(missing.message).to eq("Paste a BallDontLie key first.")
    end

    it "does not test a key once the month's budget is used up" do
      ApiUsage.create!(provider: "sports_game_odds", period: ApiUsage.period_for(Time.current), units_used: 2500, units_limit: 2500)
      r = described_class.call("sports_game_odds", transport: transport("/events" => {}))
      expect([ r.ok, r.message ]).to match([ false, /budget is used up/ ])
    end
  end

  describe Setup do
    it "starts with nothing chosen, treats an install that already has data as sample, and follows the environment" do
      expect([ described_class.mode, described_class.complete?, described_class.stage ]).to eq([ nil, false, :choose ])
      create(:game)
      expect([ described_class.mode, described_class.complete? ]).to eq([ "sample", true ])
      stub_const("ENV", ENV.to_h.merge("LIVE_DATA" => "true"))
      expect([ described_class.mode, described_class.complete? ]).to eq([ "live", true ])
    end

    it "only requires setup (and only in the one-person mode that enables it) until it is complete" do
      allow(Rails.configuration.x).to receive(:require_setup).and_return(true)
      expect(described_class.required?).to be(true)
      Setting.set("data_mode", "sample")
      expect(described_class.required?).to be(false)
    end

    it "moves from choosing, to keys, to history, to done" do
      expect(described_class.stage).to eq(:choose)
      described_class.choose_live
      expect(described_class.stage).to eq(:keys)

      described_class.verify("sports_game_odds", checker: checker(sports_game_odds: result))
      expect(described_class.stage).to eq(:keys) # BallDontLie not tested yet
      described_class.verify("balldontlie", checker: checker(balldontlie: result(box_scores: true)))
      expect(described_class.keys_ready?).to be(true)
      expect(described_class.stage).to eq(:backfill)

      described_class.go_live
      expect([ described_class.live?, LiveData.enabled?, described_class.complete?, described_class.stage ]).to eq([ true, true, false, :backfill ])

      BackfillRun.create!(state: "done")
      described_class.finish_live
      expect([ described_class.complete?, described_class.stage ]).to eq([ true, :done ])
    end

    it "does not count a free BallDontLie plan, or a failed test, as ready" do
      described_class.verify("sports_game_odds", checker: checker(sports_game_odds: result))
      described_class.verify("balldontlie", checker: checker(balldontlie: result(box_scores: false)))
      expect([ described_class.check("balldontlie"), described_class.keys_ready? ]).to eq([ "no_box_scores", false ])

      described_class.verify("balldontlie", checker: checker(balldontlie: result(ok: false)))
      expect(described_class.check("balldontlie")).to be_nil
    end

    it "forgets a test result when the key changes, and ignores a blank box" do
      described_class.verify("sports_game_odds", checker: checker(sports_game_odds: result))
      described_class.save_key("sports_game_odds", "")
      expect(described_class.check("sports_game_odds")).to eq("ok")
      described_class.save_key("sports_game_odds", "new-key")
      expect([ described_class.check("sports_game_odds"), ApiKeys.get("sports_game_odds") ]).to eq([ nil, "new-key" ])
    end

    it "loads sample data only when there is none, and switches back from live" do
      seeded = 0
      seeder = -> { seeded += 1 }
      Setting.set("data_mode", "live")
      described_class.use_sample(seeder: seeder)
      expect([ described_class.mode, LiveData.enabled?, seeded ]).to eq([ "sample", false, 1 ])
      create(:game)
      described_class.use_sample(seeder: seeder)
      expect(seeded).to eq(1)
    end
  end
end
