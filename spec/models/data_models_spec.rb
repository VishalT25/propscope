require "rails_helper"

RSpec.describe "Data models" do
  describe Game do
    it "stores slate_date as the US Eastern date" do
      game = create(:game, starts_at: Time.utc(2026, 11, 10, 2, 30)) # 9:30pm ET on Nov 9
      expect(game.slate_date).to eq(Date.new(2026, 11, 9))
    end

    it "rejects a team playing itself" do
      team = create(:team)
      expect(build(:game, home_team: team, away_team: team)).not_to be_valid
    end

    it "enforces one game per matchup per slate" do
      game = create(:game)
      dup = build(:game, sport: game.sport, home_team: game.home_team, away_team: game.away_team, starts_at: game.starts_at)
      dup.slate_date = game.slate_date
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "scopes upcoming games to the next 36h" do
      soon = create(:game, starts_at: 5.hours.from_now)
      create(:game, starts_at: 50.hours.from_now)
      create(:game, starts_at: 1.hour.ago)
      expect(described_class.upcoming).to eq([ soon ])
    end
  end

  describe Player do
    it "derives normalized_name on save" do
      expect(create(:player, first_name: "Dušan", last_name: "Marković Jr.").normalized_name).to eq("dusan markovic")
    end
  end

  describe Market do
    it "requires a player for player props and a line for non-moneylines" do
      game = create(:game)
      expect(build(:market, game: game, player: nil, market_type: "player_points")).not_to be_valid
      expect(build(:market, game: game, player: nil, market_type: "spread", line: nil)).not_to be_valid
      expect(build(:market, game: game, player: nil, market_type: "moneyline", line: nil)).to be_valid
    end

    it "is unique on its natural key, including NULL lines and players" do
      game = create(:game)
      create(:market, game: game, player: nil, market_type: "moneyline", line: nil)
      expect { create(:market, game: game, player: nil, market_type: "moneyline", line: nil) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same player and stat at different lines" do
      market = create(:market, line: 24.5)
      expect { create(:market, game: market.game, player: market.player, line: 25.5) }.not_to raise_error
    end
  end

  describe PlayerGameLog do
    it "excludes DNPs from the played scope" do
      create(:player_game_log, minutes: 0, points: 0)
      played = create(:player_game_log, minutes: 31)
      expect(described_class.played).to eq([ played ])
    end

    it "is unique per player and game" do
      log = create(:player_game_log)
      expect { create(:player_game_log, player: log.player, game: log.game) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ExternalId do
    it "is unique per provider, type and id, and re-registering repoints it" do
      a, b = create_list(:team, 2)
      described_class.register!("p", "team", 1, a)
      described_class.register!("p", "team", 1, b)
      expect(described_class.count).to eq(1)
      expect(described_class.lookup("p", "team", "1")).to eq(b)
    end

    it "returns nil for unknown ids" do
      expect(described_class.lookup("p", "team", "nope")).to be_nil
    end
  end

  describe UnresolvedEntity do
    it "upserts by provider/type/id and can be resolved" do
      2.times { described_class.record!(provider: "p", type: "player", external_id: "1", payload: { n: 1 }, reason: "r") }
      expect(described_class.count).to eq(1)
      described_class.first.resolve!
      expect(described_class.open).to be_empty
    end
  end

  describe RawPayload do
    it "marks payloads older than 14 days as expired" do
      old = RawPayloadStore.capture(provider: "p", endpoint: "/e", params: { b: 1, a: 2 }, status: 200, body: { x: 1 }, fetched_at: 20.days.ago)
      expect(described_class.expired).to eq([ old ])
    end

    it "digests params independent of key order" do
      a = RawPayloadStore.capture(provider: "p", endpoint: "/e", params: { b: 1, a: 2 }, status: 200, body: {})
      b = RawPayloadStore.capture(provider: "p", endpoint: "/e", params: { a: 2, b: 1 }, status: 200, body: {})
      expect(a.params_digest).to eq(b.params_digest)
    end
  end

  describe ApiUsage do
    it "computes percent used, nil without a cap" do
      expect(described_class.new(units_used: 50, units_limit: 200).percent_used).to eq(25.0)
      expect(described_class.new(units_used: 50, units_limit: nil).percent_used).to be_nil
    end
  end

  describe Bookmaker do
    it "creates unknown books on first sight with a text badge" do
      book = described_class.for_key("draftkings")
      expect(book).to have_attributes(name: "DraftKings", code: "DK", kind: "sportsbook", sharp: false)
      expect(described_class.for_key("draftkings")).to eq(book)
      expect(described_class.for_key("mystery_book")).to have_attributes(name: "Mystery Book", code: "MYS")
    end
  end
end
