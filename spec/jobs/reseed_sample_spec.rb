require "rails_helper"

RSpec.describe "Keeping sample data current" do
  include ActiveSupport::Testing::TimeHelpers

  def upcoming_markets = Market.joins(:game).where("games.starts_at > ?", Time.current).count

  describe ReseedSampleJob do
    it "re-dates the sample slate only for an install that chose sample data" do
      allow(Ingest::SeedFixtures).to receive(:call)
      described_class.perform_now # nothing chosen
      Setting.set("data_mode", "live")
      described_class.perform_now # live data must never get fixtures mixed in
      expect(Ingest::SeedFixtures).not_to have_received(:call)

      Setting.set("data_mode", "sample")
      described_class.perform_now
      expect(Ingest::SeedFixtures).to have_received(:call).once
    end

    it "slides the same sample world forward to a later day, without piling up duplicates" do
      Ingest::SeedFixtures.call(today: Date.current + 1)
      games = Game.count
      expect(upcoming_markets).to be_positive

      travel_to(3.days.from_now) do
        expect(Setup.sample_fresh?).to be(false) # the first slate is behind us
        Ingest::SeedFixtures.call(today: Date.current + 1)
        expect(Setup.sample_fresh?).to be(true)
      end
      expect(Game.count).to eq(games)
    end
  end

  describe Setup do
    before { Setting.set("data_mode", "sample") }

    it "knows whether the sample slate is still ahead of us" do
      expect(described_class.sample_fresh?).to be(false)
      market = create(:market)
      market.game.update!(starts_at: 3.hours.from_now)
      expect(described_class.sample_fresh?).to be(true)
      market.game.update!(starts_at: 3.hours.ago)
      expect(described_class.sample_fresh?).to be(false)
    end

    it "queues a re-date when the slate has gone by, but at most every 15 minutes" do
      expect { described_class.refresh_sample_if_stale }.to have_enqueued_job(ReseedSampleJob)
      expect { described_class.refresh_sample_if_stale }.not_to have_enqueued_job(ReseedSampleJob)
      expect { described_class.refresh_sample_if_stale(now: 16.minutes.from_now) }.to have_enqueued_job(ReseedSampleJob)
    end

    it "leaves a fresh slate, live data, and an install that never chose sample data alone" do
      create(:market).game.update!(starts_at: 3.hours.from_now)
      expect { described_class.refresh_sample_if_stale }.not_to have_enqueued_job(ReseedSampleJob)

      Market.destroy_all
      Setting.set("data_mode", "live")
      expect { described_class.refresh_sample_if_stale }.not_to have_enqueued_job(ReseedSampleJob)

      Setting.delete("data_mode")
      create(:game) # inferred sample, as an older install would be
      expect { described_class.refresh_sample_if_stale }.not_to have_enqueued_job(ReseedSampleJob)
    end

    it "re-loads when sample data is chosen again and its slate has gone by" do
      seeded = 0
      described_class.use_sample(seeder: -> { seeded += 1 })
      create(:market).game.update!(starts_at: 3.hours.from_now)
      described_class.use_sample(seeder: -> { seeded += 1 })
      expect(seeded).to eq(1)
    end
  end

  describe "when a page is viewed", type: :request do
    before { allow(Rails.configuration.x).to receive(:single_user).and_return(true) }

    it "re-dates a stale sample install in the background" do
      Setting.set("data_mode", "sample")
      expect { get "/nba/props" }.to have_enqueued_job(ReseedSampleJob)
      expect(response).to have_http_status(:ok)
    end

    it "does not do it for the health check" do
      Setting.set("data_mode", "sample")
      expect { get "/up" }.not_to have_enqueued_job(ReseedSampleJob)
    end
  end
end

RSpec.describe "Running it yourself, safely", type: :request do
  it "shows a gambling disclaimer and helplines on every page" do
    allow(Rails.configuration.x).to receive(:single_user).and_return(true)
    get "/"
    expect(response.body).to include("not betting advice", "afford to lose", "National Council on Problem Gambling", "ConnexOntario")
  end

  it "publishes the Docker port on this computer only, unless the person opts out" do
    expect(Rails.root.join("docker-compose.yml").read).to include('"${BIND_ADDRESS:-127.0.0.1}:${PORT:-3000}:80"')
  end
end
