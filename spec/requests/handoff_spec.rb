require "rails_helper"

RSpec.describe "Sending the slip to a sportsbook" do
  let(:user) { User.local }
  let(:fd) { create(:bookmaker, key: "fanduel", code: "FD", name: "FanDuel") }
  let(:dk) { create(:bookmaker, key: "draftkings", code: "DK", name: "DraftKings") }
  let(:game) { create(:game, starts_at: 5.hours.from_now) }

  before { allow(Rails.configuration.x).to receive(:single_user).and_return(true) }

  def leg(fd_ids: nil, dk_better: false)
    player = create(:player, sport: game.sport, team: game.home_team)
    market = create(:market, game: game, player: player, line: 24.5)
    link = fd_ids && "https://sportsbook.fanduel.com/addToBetslip?marketId=#{fd_ids[0]}&selectionId=#{fd_ids[1]}"
    create(:odds_snapshot, market: market, bookmaker: fd, outcome: "over", american_odds: -110, decimal_odds: OddsMath.american_to_decimal(-110), line: 24.5, deeplink: link) if fd_ids
    create(:odds_snapshot, market: market, bookmaker: dk, outcome: "over", american_odds: dk_better ? 120 : -130, decimal_odds: OddsMath.american_to_decimal(dk_better ? 120 : -130), line: 24.5,
                           deeplink: "https://sportsbook.draftkings.com/event/35003210?outcomes=0QA388474837")
    user.picks.create!(market: market, side: "over", bookmaker: fd, price_at_add: -110)
    player
  end

  def slip_html = response.body[%r{<dialog id="picks_slip".*?</dialog>}m]

  it "puts a FanDuel link, a way to copy it and a QR code in the slip, for the viewer's region" do
    leg(fd_ids: [ "42.624795660", "12260618" ])
    leg(fd_ids: [ "42.624790148", "61967199" ])
    user.update!(region: "on")
    get "/nba/props"
    html = slip_html
    expect(html).to include("Send to a sportsbook", "FanDuel", "2 of 2 legs available", "Add all 2 legs to FanDuel", "Copy link", "Open on your phone (QR code)")
    expect(html).to include("https://on.sportsbook.fanduel.ca/addToBetslip?marketId[0]=42.624795660&amp;selectionId[0]=12260618&amp;marketId[1]=42.624790148&amp;selectionId[1]=61967199")
    expect(html).to include('aria-label="QR code that opens this slip at FanDuel"')
    expect(html).to include("Links for <b class=\"text-fg\">Ontario</b>", "nothing is placed for you")
    expect(html).not_to match(/shareBetId|partner_/)
  end

  it "uses the United States address until another region is chosen" do
    leg(fd_ids: [ "42.1", "11" ])
    get "/nba/props"
    expect(slip_html).to include("https://sportsbook.fanduel.com/addToBetslip?marketId[0]=42.1&amp;selectionId[0]=11")
    expect(slip_html).to include("Links for <b class=\"text-fg\">United States</b>")
  end

  it "keeps the QR code and the link in step: the code is drawn from the same address the button opens" do
    leg(fd_ids: [ "42.1", "11" ])
    get "/nba/props"
    expect(slip_html.scan("addToBetslip?marketId[0]=42.1&amp;selectionId[0]=11").size).to be >= 2 # the button and the copy text
    expect(slip_html).to match(%r{<svg[^>]*role="img"})
  end

  it "says which leg FanDuel is not offering, and links the rest" do
    leg(fd_ids: [ "42.1", "11" ])
    missing = leg
    get "/nba/props"
    expect(slip_html).to include("1 of 2 legs available", "Add 1 of 2 legs to FanDuel", "Not offered at FanDuel right now: #{missing.full_name}")
  end

  it "never shows DraftKings links, even when DraftKings has the best price for a leg" do
    leg(fd_ids: [ "42.1", "11" ], dk_better: true)
    get "/nba/props"
    expect(slip_html).not_to include("draftkings.com")
    expect(slip_html).not_to include("Add all 1 legs to DraftKings")
    get "/picks", params: { book: "draftkings" }
    expect(response.body).not_to include("draftkings.com")
    expect(response.body).not_to include(">Open<")
  end

  it "shows nothing to send when no leg has a FanDuel link" do
    leg
    get "/nba/props"
    expect(slip_html).not_to include("Send to a sportsbook")
  end

  describe "the region setting" do
    it "is changed from the account menu, and only to a known place" do
      get "/nba/props"
      expect(response.body).to include("Where you bet", "Ontario", "United States", "Sportsbooks are licensed per province and state")
      patch "/preferences", params: { region: "on" }
      expect(user.reload.region).to eq("on")
      patch "/preferences", params: { region: "mars" }
      expect(user.reload.region).to eq("on")
      patch "/preferences", params: { odds_format: "decimal" }
      expect(user.reload.region).to eq("on") # another preference leaves it alone
    end

    it "marks the current region in the menu" do
      user.update!(region: "on")
      get "/nba/props"
      menu = response.body[%r{aria-label="Region".*?</div>}m]
      expect(menu).to match(/aria-pressed="true"[^>]*>\s*Ontario|Ontario[^<]*<\/button>/)
      expect(menu.scan('aria-pressed="true"').size).to eq(1)
    end

    it "is not offered to a guest, who has no slip" do
      allow(Rails.configuration.x).to receive(:single_user).and_return(false)
      get "/nba/props"
      expect(response.body).not_to include("Where you bet")
    end
  end
end
