require "rails_helper"

RSpec.describe "Slip, picks and single-user mode" do
  seed_fixtures_once

  let(:market) { Market.joins(:game).where("games.starts_at > now()").where(market_type: "player_points").first }
  let(:stream) { { "Accept" => "text/vnd.turbo-stream.html" } }

  def single_user!(on = true)
    allow(Rails.configuration.x).to receive(:single_user).and_return(on)
  end

  describe "single-user mode (the self-hosted default)" do
    before { single_user! }

    it "needs no sign-in: the + works for a visitor and the page never shows account links" do
      get "/nba/props"
      expect(response.body).not_to include("Sign in", "Create account", "Log out")
      post "/picks", params: { market_id: market.id, side: "over" }, headers: stream
      expect(response).to have_http_status(:ok)
      expect(User.local.picks.count).to eq(1)
    end

    it "keeps picks, books and saved filters on the one local user" do
      patch "/books", params: { keys: [ "caesars" ] }
      post "/saved_filters", params: { name: "mine", side: "over" }
      expect(User.local.enabled_bookmaker_keys).to eq([ "caesars" ])
      expect(User.local.saved_filters.pluck(:name)).to eq([ "mine" ])
    end

    it "turns the account pages off" do
      get "/session/new"
      expect(response).to redirect_to(root_path)
      get "/registration/new"
      expect(response).to redirect_to(root_path)
      expect(User.count).to be <= 1 # only the local user could exist
    end

    it "the + replaces itself in place, updates the count and the slip (Turbo Stream, no page reload)" do
      post "/picks", params: { market_id: market.id, side: "over" }, headers: stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      html = CGI.unescapeHTML(response.body)
      expect(html).to include("data-pick='#{market.id}-over'", "leg-added", 'target="picks_count"', 'target="slip"', "Added to your slip.")
    end

    it "clicking the added leg again removes it" do
      post "/picks", params: { market_id: market.id, side: "over" }
      pick = User.local.picks.first
      delete "/picks/#{pick.id}", headers: stream
      expect(User.local.picks.count).to eq(0)
      expect(response.body).to include("Add to your slip")
    end

    it "keeps the + inside the Turbo Frame so it can never produce 'Content missing'" do
      get "/nba/props"
      expect(response.body).not_to match(%r{href="/session/new"})
      expect(response.body).to include("Add to your slip")
    end
  end

  describe "multi-user mode" do
    before { single_user!(false) }
    let(:user) { create(:user) }

    it "still requires a login to add picks" do
      post "/picks", params: { market_id: market.id, side: "over" }
      expect(response).to redirect_to(new_session_path)
    end

    it "works for a signed-in user, and cannot touch someone else's pick" do
      post session_path, params: { email_address: user.email_address, password: "password123" }
      post "/picks", params: { market_id: market.id, side: "over" }
      expect(user.picks.count).to eq(1)
      other = Pick.create!(user: create(:user), market: market, side: "under", bookmaker: Bookmaker.first, price_at_add: -110)
      delete "/picks/#{other.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the slip" do
    before { single_user! }

    def add(m = market, side = "over") = post("/picks", params: { market_id: m.id, side: side }, headers: stream)

    it "shows legs, the best price, parlay odds and the payout for the stake" do
      add
      other = Market.joins(:game).where("games.starts_at > now()").where(market_type: "player_assists").first
      add(other)
      get "/picks", params: { stake: 20 }
      expect(response.body).to include("2-leg parlay", "stake pays", "Copy slip", "Best price for each leg")
      expect(response.body).to match(/\$20\.00 stake pays/)
    end

    it "remembers the chosen book and stake" do
      add
      book = BestPrice.current_snapshots(market_ids: [ market.id ]).find { |s| s.outcome == "over" }.bookmaker
      get "/picks", params: { book: book.key, stake: 50 }
      expect(response.body).to include("at #{book.name}")
      get "/nba/props"
      expect(response.body).to include("value=\"50\"")
      expect(cookies[:slip_book]).to eq(book.key)
    end

    it "offers an Open link only for a book we can send people to, built from the ids in its link and never from its address" do
      add
      snaps = BestPrice.current_snapshots(market_ids: [ market.id ]).select { |s| s.outcome == "over" }
      fd = snaps.find { |s| s.bookmaker.key == "fanduel" }
      other = snaps.find { |s| s.bookmaker.key != "fanduel" }

      get "/picks", params: { book: fd.bookmaker.key }
      expect(response.body).not_to include(">Open<") # no booking link yet
      OddsSnapshot.find(fd.id).update!(deeplink: "https://evil.test/addToBetslip?marketId=42.1&selectionId=77")
      get "/picks", params: { book: fd.bookmaker.key }
      expect(response.body).to include("https://sportsbook.fanduel.com/addToBetslip?marketId[0]=42.1&amp;selectionId[0]=77", 'rel="noopener noreferrer"', 'target="_blank"')
      expect(response.body).not_to include("evil.test")

      OddsSnapshot.find(other.id).update!(deeplink: "https://book.test/slip?leg=1") # a book whose links we have not verified
      get "/picks", params: { book: other.bookmaker.key }
      expect(response.body).not_to include("book.test")
      expect(response.body).not_to include(">Open<")
    end

    it "copies a plain-text slip with the legs, prices and parlay" do
      add
      get "/nba/props"
      text = CGI.unescapeHTML(response.body[/data-clipboard-text-value="([^"]*)"/, 1].to_s)
      expect(text).to include("Slip", market.player.full_name, "over", "Single")
    end

    it "is an empty state with no legs" do
      get "/picks"
      expect(response.body).to include("Your slip is empty")
    end
  end
end
