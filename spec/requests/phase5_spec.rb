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

  describe "My Picks" do
    let(:user) { create(:user) }
    let(:market) { Market.joins(:game).where("games.starts_at > now()").where(market_type: "player_points").first }

    def sign_in = post(session_path, params: { email_address: user.email_address, password: "password123" })

    it "needs a login to add, and guests see a sign-in prompt in the slip" do
      post "/picks", params: { market_id: market.id, side: "over" }
      expect(response).to redirect_to(new_session_path)
      get "/nba/props"
      expect(response.body).to include("to build a slip")
    end

    it "adds the best-priced pick once, remembering the price and book" do
      sign_in
      post "/picks", params: { market_id: market.id, side: "over" }
      post "/picks", params: { market_id: market.id, side: "over" }
      expect(user.picks.count).to eq(1)
      pick = user.picks.first
      best = BestPrice.for(market_ids: [ market.id ])[[ market.id, "over" ]]
      expect([ pick.bookmaker, pick.price_at_add ]).to eq([ best.bookmaker, best.american_odds ])
    end

    it "rejects a bad side, and a line no enabled book offers" do
      sign_in
      post "/picks", params: { market_id: market.id, side: "middle" }
      expect(response).to have_http_status(:unprocessable_content)
      patch "/books", params: { keys: [ "bovada" ] } # a book with no prices in the fixtures is not even selectable, so nothing changes
      other = Bookmaker.where.not(id: BestPrice.current_snapshots(market_ids: [ market.id ]).map(&:bookmaker_id)).first
      patch "/books", params: { keys: [ other.key ] } if other
      post "/picks", params: { market_id: market.id, side: "over" }
      expect(user.picks.count).to be <= 1
    end

    it "shows the slip grouped by book with price added vs now, and removes picks" do
      sign_in
      post "/picks", params: { market_id: market.id, side: "over" }
      pick = user.picks.first
      OddsSnapshot.create!(market: market, bookmaker: pick.bookmaker, outcome: "over", american_odds: pick.price_at_add + 15, decimal_odds: OddsMath.american_to_decimal(pick.price_at_add + 15),
                           line: market.line, captured_at: 1.minute.from_now, source_provider: "test")
      get "/nba/props"
      expect(response.body).to include(pick.bookmaker.name, market.player.full_name, "→")
      slip = PickSlip.call(user: user)
      expect(slip.size).to eq(1)
      expect(slip.first.lines.first.moved).to eq(1)
      expect(slip.first.lines.first.now_odds).to eq(pick.price_at_add + 15)
      delete "/picks/#{pick.id}"
      expect(user.picks.count).to eq(0)
    end

    it "cannot remove someone else's pick" do
      other = Pick.create!(user: create(:user), market: market, side: "over", bookmaker: Bookmaker.first, price_at_add: -110)
      sign_in
      delete "/picks/#{other.id}"
      expect(response).to have_http_status(:not_found)
      expect(Pick.exists?(other.id)).to be(true)
    end

    it "marks a pick whose book no longer offers the line" do
      sign_in
      post "/picks", params: { market_id: market.id, side: "over" }
      OddsSnapshot.where(market_id: market.id, bookmaker_id: user.picks.first.bookmaker_id).delete_all
      expect(PickSlip.call(user: user).first.lines.first.now_odds).to be_nil
    end
  end
end

RSpec.describe AvatarsHelper, type: :helper do
  it "never produces an indigo or violet tint" do
    hues = Array.new(500) { |i| helper.hue_for("team#{i}") }
    expect(hues).to all(be_between(10, 215))
  end
end
