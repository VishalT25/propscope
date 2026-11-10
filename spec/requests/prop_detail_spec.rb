require "rails_helper"

RSpec.describe "Prop detail" do
  seed_fixtures_once

  let(:market) { Market.joins(:game).where("games.starts_at > now()").where(market_type: "player_points").order(:id).first }

  it "renders header, charts, defence card, movement and history for both sides" do
    %w[over under].each do |side|
      get "/nba/props/#{market.id}/#{side}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(market.player.full_name, "defense", "Consensus line movement", "data-testid=\"bars-chart\"", "All books")
    end
  end

  it "switches windows and shows an empty state where there are no games" do
    get "/nba/props/#{market.id}/over", params: { window: "prev_season" }
    expect(response.body).to include("No games in this window yet")
    get "/nba/props/#{market.id}/over", params: { window: "l5" }
    expect(response.body).to include("data-testid=\"bars-chart\"")
  end

  it "ignores bad params and 404s on bad ids or sides" do
    get "/nba/props/#{market.id}/over", params: { window: "zzz", support: "zzz", pos: "zzz" }
    expect(response).to have_http_status(:ok)
    get "/nba/props/999999/over"
    expect(response).to have_http_status(:not_found)
    get "/nba/props/#{market.id}/middle"
    expect(response).to have_http_status(:not_found)
  end

  it "never calls an external API" do
    allow(Providers::Registry).to receive(:for).and_raise("no provider calls on page requests")
    get "/nba/props/#{market.id}/over"
    expect(response).to have_http_status(:ok)
  end

  it "builds the same games the hit rate uses, with closing-line results" do
    detail = PropDetail.call(market: market, side: "over", window: "l10")
    expect(detail.bars.size).to eq(detail.summary.hits + detail.summary.misses + detail.summary.pushes)
    expect(detail.summary.closing_n).to be > 0
  end
end

RSpec.describe AvatarsHelper, type: :helper do
  it "draws monogram avatars without third-party images, and prefers a supplied photo" do
    player = build(:player, first_name: "Dušan", last_name: "Marković", team: build(:team, abbreviation: "BOS"))
    expect(helper.player_avatar(player)).to include(">DM<", "BOS")
    player.photo_url = "https://example.test/p.png"
    expect(helper.player_avatar(player)).to include("https://example.test/p.png")
  end

  it "gives a stable tint per code" do
    expect(helper.tint_style("BOS")).to eq(helper.tint_style("BOS"))
    expect(helper.tint_style("BOS")).not_to eq(helper.tint_style("LAL"))
  end
end
