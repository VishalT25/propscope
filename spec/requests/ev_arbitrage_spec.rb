require "rails_helper"

RSpec.describe "EV+ and Arbitrage pages" do
  seed_fixtures_once

  it "renders EV+ cards with fair price, EV, Kelly and the odds details" do
    get "/nba/ev"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("EV+", "vs fair", "Kelly", "Odds details", "no sharp book on the free data tier")
    expect(response.body).to match(/\d+\.\d{2}%/)
  end

  it "honours the filters and survives garbage" do
    get "/nba/ev", params: { min_ev: 99, method: "power" }
    expect(response.body).to include("No +EV prices right now")
    get "/nba/ev", params: { min_ev: "x", method: "zzz", kelly: "9", min_books: "q", side: "sideways", page: "-3", sort: "evil" }
    expect(response).to have_http_status(:ok)
  end

  it "uses only the books the viewer enabled for the offered price" do
    patch "/books", params: { keys: [ "caesars" ] }
    get "/nba/ev"
    expect(response.body).to include("CZR")
  end

  it "renders arbitrage with stake splits that follow the stake input" do
    get "/nba/arbitrage", params: { stake: 100 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stake", "To win", "get back at least")
    get "/nba/arbitrage", params: { stake: 500, min_profit: 3 }
    expect(response.body).to include("$500.00")
  end

  it "clamps silly stakes and margins" do
    get "/nba/arbitrage", params: { stake: "-5", min_profit: "abc" }
    expect(response.body).to include("$1.00")
    get "/nba/arbitrage", params: { stake: "999999999", min_profit: "500" }
    expect(response).to have_http_status(:ok)
  end

  it "never calls an external API" do
    allow(Providers::Registry).to receive(:for).and_raise("no provider calls on page requests")
    get "/nba/ev"
    get "/nba/arbitrage"
    expect(response).to have_http_status(:ok)
  end

  it "is linked from the menu" do
    get "/nba/props"
    expect(response.body).to include("/nba/ev", "/nba/arbitrage")
    expect(response.body).not_to include(">Soon<")
  end
end
