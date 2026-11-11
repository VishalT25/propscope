require "rails_helper"

RSpec.describe "Home and saved slips" do
  let(:stream) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:user) { User.local }
  let(:fd) { create(:bookmaker, key: "fd", code: "FD", name: "FanDuel") }
  let(:game) { create(:game, starts_at: 5.hours.from_now) }

  before { allow(Rails.configuration.x).to receive(:single_user).and_return(true) }

  def add_pick(price = 110)
    market = create(:market, game: game, player: create(:player, sport: game.sport, team: game.home_team), line: 24.5)
    create(:odds_snapshot, market: market, bookmaker: fd, outcome: "over", american_odds: price, decimal_odds: OddsMath.american_to_decimal(price), line: 24.5)
    user.picks.create!(market: market, side: "over", bookmaker: fd, price_at_add: price)
    market
  end

  it "is the landing page, with an empty state that points at the props" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No saved slips yet", "Browse props")
    expect(response.body).to include('aria-current="page"') # Home is the lit nav link
  end

  it "saves the working slip from the drawer, keeps the picks, and shows it on Home" do
    add_pick(110)
    add_pick(-120)
    cookies[:slip_book] = "fd"
    post "/slips", params: { name: "Friday night" }, headers: stream
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(CGI.unescapeHTML(response.body)).to include("Saved “Friday night”")
    expect(user.picks.count).to eq(2)

    get "/"
    expect(response.body).to include("Friday night", "In play", "Pending", "+110", "-120")
    expect(response.body).not_to include("No saved slips yet")
  end

  it "explains why a slip cannot be saved instead of saving a half-priced one" do
    offered = add_pick
    add_pick
    dk = create(:bookmaker, key: "dk", code: "DK") # offers only one of the two legs
    create(:odds_snapshot, market: offered, bookmaker: dk, outcome: "over", american_odds: 115, decimal_odds: OddsMath.american_to_decimal(115), line: 24.5)
    cookies[:slip_book] = dk.key
    post "/slips", params: { name: "x" }, headers: stream
    expect(response.body).to include("current price")
    expect(Slip.count).to eq(0)
  end

  it "shows graded legs, the result and the payout under Settled" do
    add_pick(100)
    post "/slips", params: { name: "Graded" }
    slip = Slip.last
    leg = slip.legs.first
    create(:player_game_log, player: leg.market.player, game: leg.market.game, points: 30)
    Slips::Grade.call

    get "/"
    expect(response.body).to include("Settled", "Won", "Hit", "30", "$20.00")
    expect(response.body).not_to include(">In play<")
  end

  it "deletes a saved slip" do
    add_pick
    post "/slips", params: { name: "Gone" }
    delete "/slips/#{Slip.last.id}"
    expect(response).to redirect_to(root_path)
    expect(Slip.count).to eq(0)
  end

  it "never shows or deletes another user's slip" do
    other = create(:user)
    market = add_pick
    saved = other.slips.create!(name: "Theirs", stake: 10, decimal_odds: 2).tap { |s| s.legs.create!(market: market, bookmaker: fd, side: "over", line: 24.5, american_odds: 100, decimal_odds: 2) }
    get "/"
    expect(response.body).not_to include("Theirs")
    delete "/slips/#{saved.id}"
    expect(response).to have_http_status(:not_found)
    expect(Slip.exists?(saved.id)).to be(true)
  end

  it "asks a guest to sign in when accounts are on" do
    allow(Rails.configuration.x).to receive(:single_user).and_return(false)
    get "/"
    expect(response.body).to include("Sign in to keep your slips")
  end
end
