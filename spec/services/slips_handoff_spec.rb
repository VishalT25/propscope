require "rails_helper"

RSpec.describe "Sending a slip to a sportsbook" do
  let(:ontario) { Region.find("on") }
  let(:us) { Region.find("us") }

  def snapshot(deeplink)
    build(:odds_snapshot, bookmaker: build(:bookmaker, key: "fanduel"), deeplink: deeplink)
  end

  def fd_link(market, selection) = "https://sportsbook.fanduel.com/addToBetslip?marketId=#{market}&selectionId=#{selection}"

  describe Region do
    it "knows Ontario and the United States, and falls back to the United States" do
      expect(described_class.keys).to eq(%w[on us])
      expect([ ontario.name, ontario.fanduel_host ]).to eq([ "Ontario", "on.sportsbook.fanduel.ca" ])
      expect(described_class.default).to eq(us)
      expect(described_class.find("mars")).to be_nil
    end

    it "is something a user can set, and only to a known place" do
      user = create(:user)
      expect([ user.region, user.region_record ]).to eq([ "us", us ])
      user.update!(region: "on")
      expect(user.region_record).to eq(ontario)
      expect(user.tap { |u| u.region = "mars" }).not_to be_valid
    end
  end

  describe Slips::FanDuelLink do
    it "opens FanDuel with every leg in the slip, in the indexed form that worked on desktop and mobile" do
      result = described_class.call(region: ontario, snapshots: [ snapshot(fd_link("42.624795660", "12260618")), snapshot(fd_link("42.624790148", "61967199")) ])
      expect(result.url).to eq("https://on.sportsbook.fanduel.ca/addToBetslip?marketId[0]=42.624795660&selectionId[0]=12260618&marketId[1]=42.624790148&selectionId[1]=61967199")
      expect([ result.used.size, result.skipped ]).to eq([ 2, [] ])
    end

    it "uses the indexed form for a single leg too (the plain form fails on a phone)" do
      expect(described_class.call(region: us, snapshots: [ snapshot(fd_link("42.1", "7")) ]).url).to eq("https://sportsbook.fanduel.com/addToBetslip?marketId[0]=42.1&selectionId[0]=7")
    end

    it "takes the address from the viewer's region, never from the stored link" do
      url = described_class.call(region: ontario, snapshots: [ snapshot("https://evil.test/addToBetslip?marketId=42.1&selectionId=7") ]).url
      expect(url).to start_with("https://on.sportsbook.fanduel.ca/")
      expect(url).not_to include("evil.test")
    end

    it "takes nothing but the two ids, and adds no partner or affiliate tag" do
      url = described_class.call(region: us, snapshots: [ snapshot("https://sportsbook.fanduel.com/addToBetslip?marketId=42.1&selectionId=7&shareBetId=partner_x&extra=1") ]).url
      expect(url).to eq("https://sportsbook.fanduel.com/addToBetslip?marketId[0]=42.1&selectionId[0]=7")
      expect(url).not_to match(/partner|affiliate|shareBetId/i)
    end

    it "skips a price with no usable link, and says which, rather than sending a half-wrong slip" do
      good = snapshot(fd_link("42.1", "7"))
      none = snapshot(nil)
      odd = snapshot("https://sportsbook.fanduel.com/addToBetslip?marketId=abc&selectionId=7")
      injected = snapshot("https://sportsbook.fanduel.com/addToBetslip?marketId=42.1%26evil%3D1&selectionId=7")
      garbage = snapshot("not a url at all %%")
      result = described_class.call(region: us, snapshots: [ good, none, odd, injected, garbage ])
      expect(result.used).to eq([ good ])
      expect(result.skipped).to eq([ none, odd, injected, garbage ])
      expect(result.url.scan("marketId[").size).to eq(1)
    end

    it "gives no link when nothing is usable" do
      expect(described_class.call(region: us, snapshots: [ snapshot(nil) ]).url).to be_nil
      expect(described_class.call(region: us, snapshots: []).url).to be_nil
    end
  end

  describe Slips::Handoff do
    let(:user) { create(:user) }
    let(:fd) { create(:bookmaker, key: "fanduel", code: "FD", name: "FanDuel") }
    let(:dk) { create(:bookmaker, key: "draftkings", code: "DK", name: "DraftKings") }
    let(:game) { create(:game, starts_at: 5.hours.from_now) }

    def leg(fd: nil, dk: nil, fd_price: -110, dk_price: -120, game: self.game)
      market = create(:market, game: game, player: create(:player, sport: game.sport, team: game.home_team), line: 24.5)
      { self.fd => [ fd_price, fd ], self.dk => [ dk_price, dk ] }.each do |book, (price, link)|
        next if price.nil?

        create(:odds_snapshot, market: market, bookmaker: book, outcome: "over", american_odds: price, decimal_odds: OddsMath.american_to_decimal(price), line: 24.5, deeplink: link)
      end
      user.picks.create!(market: market, side: "over", bookmaker: self.fd, price_at_add: fd_price || dk_price)
      market
    end

    def targets(region = us, **opts) = described_class.call(slip: PickSlip.call(user: user, **opts), region: region)

    it "offers FanDuel for a slip whose legs all have a FanDuel link, with how many legs it takes and what the slip pays there" do
      leg(fd: fd_link("42.1", "11"))
      leg(fd: fd_link("42.2", "22"))
      target = targets(ontario).sole
      expect(target.bookmaker).to eq(fd)
      expect([ target.included, target.total, target.skipped ]).to eq([ 2, 2, [] ])
      expect(target.url).to eq("https://on.sportsbook.fanduel.ca/addToBetslip?marketId[0]=42.1&selectionId[0]=11&marketId[1]=42.2&selectionId[1]=22")
      expect(target.american).to eq(OddsMath.decimal_to_american((OddsMath.american_to_decimal(-110)**2).round(4))) # two legs at -110
    end

    it "does not depend on the book the slip is priced at" do
      leg(fd: fd_link("42.1", "11"), dk: "https://sportsbook.draftkings.com/event/1?outcomes=0QA1")
      expect(targets(us, book_key: "draftkings").map { |t| t.bookmaker.key }).to eq([ "fanduel" ])
    end

    it "names a leg FanDuel is not offering, and still links the rest" do
      with = leg(fd: fd_link("42.1", "11"))
      without = leg(fd: nil, fd_price: nil, dk: "https://sportsbook.draftkings.com/event/1?outcomes=0QA1")
      target = targets.sole
      expect([ target.included, target.total ]).to eq([ 1, 2 ])
      expect(target.skipped.map { |l, reason| [ l.market.id, reason ] }).to eq([ [ without.id, :not_offered ] ])
      expect(target.url.scan("marketId[").size).to eq(1)
      expect(with).to be_present
    end

    it "says when FanDuel has a price but we have no usable link for it, and leaves that leg out of the link" do
      leg(fd: fd_link("42.1", "11"))
      unlinked = leg(fd: "https://sportsbook.fanduel.com/addToBetslip")
      target = targets.sole
      expect([ target.included, target.total ]).to eq([ 1, 2 ])
      expect(target.skipped.map { |l, reason| [ l.market.id, reason ] }).to eq([ [ unlinked.id, :no_link ] ])
    end

    it "says an alternate line has no link (SportsGameOdds gives none for those), rather than blaming the book" do
      leg(fd: fd_link("42.1", "11"))
      alt = leg(fd: nil, fd_price: -110)
      alt.update!(is_alternate: true)
      target = targets.sole
      expect(target.skipped.map { |l, reason| [ l.market.id, reason ] }).to eq([ [ alt.id, :alternate ] ])
    end

    it "leaves out a leg whose game has already started, and says so, instead of sending something FanDuel cannot add" do
      leg(fd: fd_link("42.1", "11"))
      past = leg(fd: fd_link("42.2", "22"), game: create(:game, starts_at: 2.hours.ago))
      target = targets.sole
      expect([ target.included, target.total ]).to eq([ 1, 2 ])
      expect(target.url).not_to include("42.2")
      expect(target.skipped.map { |l, reason| [ l.market.id, reason ] }).to eq([ [ past.id, :started ] ])
    end

    it "offers nothing when every leg has started" do
      leg(fd: fd_link("42.1", "11"), game: create(:game, starts_at: 1.hour.ago))
      expect(targets).to eq([])
    end

    it "never offers DraftKings, whatever links it supplied (they fail), nor a book we have not tested" do
      leg(dk: "https://sportsbook.draftkings.com/event/1?outcomes=0QA1", fd_price: nil)
      expect(targets).to eq([])
    end

    it "offers nothing for an empty slip, or when no leg has a link" do
      expect(targets).to eq([])
      leg(fd: nil)
      expect(targets).to eq([])
    end

    it "gives a leg link for FanDuel prices only" do
      fd_price = create(:odds_snapshot, bookmaker: fd, deeplink: fd_link("42.1", "7"))
      dk_price = create(:odds_snapshot, bookmaker: dk, deeplink: "https://sportsbook.draftkings.com/event/1?outcomes=0QA1")
      expect(described_class.leg_url(fd_price, region: ontario)).to eq("https://on.sportsbook.fanduel.ca/addToBetslip?marketId[0]=42.1&selectionId[0]=7")
      expect(described_class.leg_url(dk_price, region: ontario)).to be_nil
    end
  end

  describe QrHelper, type: :helper do
    it "draws an SVG that names what it opens, and a different code for a different link" do
      a = helper.qr_svg("https://on.sportsbook.fanduel.ca/addToBetslip?marketId[0]=42.1&selectionId[0]=7", label: "QR code that opens this slip")
      b = helper.qr_svg("https://on.sportsbook.fanduel.ca/addToBetslip?marketId[0]=42.2&selectionId[0]=8", label: "QR code that opens this slip")
      expect(a).to include("<svg", 'role="img"', 'aria-label="QR code that opens this slip"', "<path")
      expect(a).not_to eq(b)
      expect(a).to be_html_safe
    end
  end
end
