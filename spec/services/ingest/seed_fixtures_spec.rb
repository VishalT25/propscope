require "rails_helper"

RSpec.describe Ingest::SeedFixtures do
  it "gives a fully populated slate with no API keys and no budget spend" do
    described_class.call
    expect(Game.where(slate_date: Date.current).count).to eq(8)
    expect(PlayerGameLog.count).to be > 2000
    expect(Market.where(market_type: "player_points").count).to be > 50
    expect(OddsSnapshot.count).to be > 3000
    expect(Bookmaker.pluck(:code)).to match_array(%w[DK FD MGM CZR ESPN])
    expect(ApiUsage.count).to eq(0)

    # tricky names (accents, Jr., hyphens) resolved across providers...
    names = Market.where(market_type: "player_points").includes(:player).map { |m| m.player.full_name }.uniq
    expect(names).to include("Dušan Marković", "Jaylen Brooks Jr.", "Tyrese Gilmore-Adeyemi")
    # ...and the deliberately unmatched sample player is flagged, not guessed
    expect(UnresolvedEntity.open.pluck(:external_id)).to eq([ "UNMATCHED_ROOKIE_1_NBA" ])
  end

  it "running the whole seed twice produces no duplicates" do
    described_class.call
    counts = [ Team, Player, Game, PlayerGameLog, Market, OddsSnapshot, ExternalId ].map(&:count)
    described_class.call
    expect([ Team, Player, Game, PlayerGameLog, Market, OddsSnapshot, ExternalId ].map(&:count)).to eq(counts)
  end
end
