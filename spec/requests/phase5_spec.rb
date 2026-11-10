require "rails_helper"

RSpec.describe "Games, insights and picks" do
  seed_fixtures_once

  let(:game) { Game.where("starts_at > now()").order(:starts_at).first }
  let(:date) { game.slate_date.iso8601 }

  before(:all) { Insights::Engine.call }

  describe "games list" do
    it "shows the slate with lines, strips and a seven day strip" do
      get "/nba/games", params: { date: date }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(game.home_team.name, game.away_team.name, "Match details")
      expect(response.body).to include("Today").and include("aria-label=\"Date\"")
    end

    it "filters by team name and shows an empty state" do
      get "/nba/games", params: { date: date, q: game.home_team.name.split.last }
      expect(response.body).to include(game.home_team.name)
      get "/nba/games", params: { date: date, q: "zzzznope" }
      expect(response.body).to include("No games match")
    end

    it "falls back to today for a bad date and never calls a provider" do
      allow(Providers::Registry).to receive(:for).and_raise("no provider calls on page requests")
      get "/nba/games", params: { date: "not-a-date" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "game page" do
    it "renders every tab" do
      get "/nba/games/#{game.id}"
      expect(response.body).to include("Game lines", "Player props", "Moneyline")
      get "/nba/games/#{game.id}", params: { tab: "insights" }
      expect(response.body).to include("Insights", "strength")
      get "/nba/games/#{game.id}", params: { tab: "matchup" }
      expect(response.body).to include("Team rankings", "Team records", "will not fake them")
    end

    it "falls back to the odds tab for an unknown tab and 404s for unknown games" do
      get "/nba/games/#{game.id}", params: { tab: "bogus" }
      expect(response.body).to include("Game lines")
      get "/nba/games/0"
      expect(response).to have_http_status(:not_found)
    end

    it "links props to the detail page" do
      get "/nba/games/#{game.id}"
      expect(response.body).to match(%r{/nba/props/\d+/(over|under)})
    end
  end

  describe "insights feed" do
    it "is ranked strongest first and paginated" do
      get "/nba/insights"
      strengths = response.body.scan(%r{tabular-nums">(\d+)</span>strength}).flatten.map(&:to_i)
      expect(strengths).to eq(strengths.sort.reverse)
      expect(strengths.size).to eq(20)
      expect(response.body).to include("Page 1 of")
      get "/nba/insights", params: { page: 2 }
      expect(response.body).to include("Page 2 of")
    end

    it "filters by game, market and player and ignores garbage" do
      get "/nba/insights", params: { game_id: game.id, market_type: "player_assists" }
      expect(response).to have_http_status(:ok)
      get "/nba/insights", params: { q: "zzzznobody" }
      expect(response.body).to include("No insights match")
      get "/nba/insights", params: { page: "abc", market_type: "bogus", game_id: "x" }
      expect(response).to have_http_status(:ok)
    end
  end
end

RSpec.describe AvatarsHelper, type: :helper do
  it "never produces an indigo or violet tint" do
    hues = Array.new(500) { |i| helper.hue_for("team#{i}") }
    expect(hues).to all(be_between(10, 215))
  end
end
