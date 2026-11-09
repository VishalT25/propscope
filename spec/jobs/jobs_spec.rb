require "rails_helper"

RSpec.describe "Ingestion jobs" do
  let(:today) { Date.current }

  def counts = [ Team, Player, Game, ExternalId, PlayerGameLog, Market, OddsSnapshot ].map(&:count)

  describe SyncReferenceDataJob do
    it "loads teams, players and the schedule, and a second run creates no duplicates" do
      described_class.perform_now
      first = counts
      expect(first.first(3)).to eq([ 16, 96, Game.count ])
      expect(Game.where(slate_date: today).count).to eq(8)
      described_class.perform_now
      expect(counts).to eq(first)
    end
  end

  describe IngestGameLogsJob do
    before { SyncReferenceDataJob.perform_now }

    it "ingests a day of box scores idempotently" do
      Ingest::ReferenceData.call(events: Providers::Fixture.new.fetch_events(sport: "nba", from: today - 45, to: today))
      described_class.perform_now(today - 1)
      first = PlayerGameLog.count
      expect(first).to be > 0
      described_class.perform_now(today - 1)
      expect(PlayerGameLog.count).to eq(first)
    end

    it "defaults to yesterday's slate in US Eastern" do
      provider = instance_double(Providers::Fixture, live?: false)
      allow(Providers::Registry).to receive(:for).and_return(provider)
      expected = Time.current.in_time_zone("America/New_York").to_date - 1
      allow(provider).to receive(:fetch_game_logs).and_return([])
      described_class.perform_now
      expect(provider).to have_received(:fetch_game_logs).with(sport: "nba", date: expected)
    end
  end

  describe SnapshotOddsJob do
    before do
      SyncReferenceDataJob.perform_now
    end

    it "writes snapshots for the slate; running it twice adds nothing" do
      described_class.perform_now("morning")
      first = counts
      expect(OddsSnapshot.count).to be > 0
      described_class.perform_now("morning")
      expect(counts).to eq(first)
    end

    context "with a spy provider" do
      let(:provider) { instance_double(Providers::Fixture, live?: false, fetch_odds: []) }

      before do
        allow(Providers::Registry).to receive(:for).and_return(provider)
        Game.update_all(starts_at: 10.days.ago) # clear the fixture slate
      end

      def game_in(minutes) = create(:game, starts_at: minutes.minutes.from_now)

      it "tick fetches nothing when no game is near T-90, T-20 or tip" do
        game_in(300)
        described_class.perform_now("tick")
        expect(provider).not_to have_received(:fetch_odds)
      end

      it "tick fetches games near T-90, T-20 and tip" do
        [ 90, 20, 0 ].each do |m|
          Game.delete_all
          game_in(m)
          described_class.perform_now("tick")
        end
        expect(provider).to have_received(:fetch_odds).exactly(3).times
      end

      it "drops optional snapshots (morning, T-90) at 80% of budget but keeps T-20 and closing" do
        ApiUsage.create!(provider: "sports_game_odds", period: ApiUsage.period_for, units_used: 2000, units_limit: 2500)
        game_in(120)
        described_class.perform_now("morning")
        expect(provider).not_to have_received(:fetch_odds)

        Game.delete_all
        game_in(90)
        described_class.perform_now("tick")
        expect(provider).not_to have_received(:fetch_odds)

        Game.delete_all
        game_in(20)
        described_class.perform_now("tick")
        expect(provider).to have_received(:fetch_odds).once

        Game.delete_all
        game_in(0)
        described_class.perform_now("tick")
        expect(provider).to have_received(:fetch_odds).twice
      end

      it "uses event ids once games are mapped, a window query before" do
        game = game_in(120)
        described_class.perform_now("morning")
        expect(provider).to have_received(:fetch_odds).with(hash_including(from: anything, to: anything)).once
        ExternalId.register!("sports_game_odds", "game", "EVT-9", game)
        described_class.perform_now("morning")
        expect(provider).to have_received(:fetch_odds).with(sport: "nba", event_ids: [ "EVT-9" ]).once
      end

      it "handles BudgetExceeded gracefully instead of failing the job" do
        game_in(120)
        allow(provider).to receive(:fetch_odds).and_raise(BudgetGuard::BudgetExceeded, "out of budget")
        expect { described_class.perform_now("morning") }.not_to raise_error
      end
    end
  end

  describe "LIVE_DATA gating" do
    let(:live_provider) { instance_double(Providers::SportsGameOdds, live?: true, provider_key: "sports_game_odds", fetch_odds: []) }

    before do
      allow(Providers::Registry).to receive(:for).and_return(live_provider)
      create(:game, starts_at: 2.hours.from_now)
    end

    it "no-ops live providers unless LIVE_DATA=true" do
      SnapshotOddsJob.perform_now("morning")
      expect(live_provider).not_to have_received(:fetch_odds)
    end

    it "runs live providers when LIVE_DATA=true" do
      stub_const("ENV", ENV.to_h.merge("LIVE_DATA" => "true"))
      SnapshotOddsJob.perform_now("morning")
      expect(live_provider).to have_received(:fetch_odds)
    end
  end

  describe MarkClosingLinesJob do
    it "marks closing lines for games that have started" do
      game = create(:game, starts_at: 1.hour.ago)
      market = create(:market, game: game, player: create(:player, team: game.home_team))
      snap = create(:odds_snapshot, market: market, captured_at: 2.hours.ago)
      described_class.perform_now
      expect(snap.reload.is_closing).to be(true)
    end
  end

  describe PurgeRawPayloadsJob do
    it "deletes payloads older than 14 days and keeps recent ones" do
      old = RawPayloadStore.capture(provider: "x", endpoint: "/e", params: {}, status: 200, body: { a: 1 }, fetched_at: 15.days.ago)
      fresh = RawPayloadStore.capture(provider: "x", endpoint: "/e", params: {}, status: 200, body: { a: 2 }, fetched_at: 13.days.ago)
      described_class.perform_now
      expect(RawPayload.exists?(old.id)).to be(false)
      expect(RawPayload.exists?(fresh.id)).to be(true)
    end
  end

  it "schedules every job in recurring.yml for production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    classes = schedule.values.filter_map { |t| t["class"] }
    expect(classes).to include("SyncReferenceDataJob", "IngestGameLogsJob", "SnapshotOddsJob", "MarkClosingLinesJob", "PurgeRawPayloadsJob")
    expect(schedule["odds_morning"]["schedule"]).to include("America/New_York")
    classes.each { |c| expect { c.constantize }.not_to raise_error }
  end
end
