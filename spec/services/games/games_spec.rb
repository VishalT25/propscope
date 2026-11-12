require "rails_helper"

RSpec.describe "Game services" do
  let(:sport) { create(:sport) }
  let(:home) { create(:team, sport: sport, abbreviation: "HOM", name: "Home Hawks") }
  let(:away) { create(:team, sport: sport, abbreviation: "AWY", name: "Away Owls") }
  let(:game) { create(:game, sport: sport, home_team: home, away_team: away, starts_at: 5.hours.from_now, season: 2026) }
  let(:dk) { create(:bookmaker, key: "dk", code: "DK") }
  let(:fd) { create(:bookmaker, key: "fd", code: "FD") }

  def market(type, line) = create(:market, game: game, player: nil, market_type: type, line: line)

  def price(market, outcome, odds, book = dk)
    create(:odds_snapshot, market: market, bookmaker: book, outcome: outcome, american_odds: odds, decimal_odds: OddsMath.american_to_decimal(odds), line: market.line)
  end

  def final(team_home, team_away, hs, as, days_ago)
    create(:game, sport: sport, home_team: team_home, away_team: team_away, home_score: hs, away_score: as, status: "final", season: 2026, starts_at: game_time(days_ago))
  end

  # Midday Eastern, N days back: the same hour every day, so two different days can never land on one slate date (a clock change or the
  # time of day the suite runs at used to be able to do that).
  def game_time(days_ago) = (Time.current.in_time_zone(Game::SLATE_ZONE).to_date - days_ago).in_time_zone(Game::SLATE_ZONE).change(hour: 12)

  describe Games::Lines do
    it "picks, per side, the line most books agree on, with its best price" do
      main = market("spread", -3.5)
      alt = market("spread", -4.5)
      [ dk, fd ].each { |b| price(main, "home", -110, b) }
      price(main, "home", -105, fd)
      price(alt, "home", +120, create(:bookmaker)) # a third book quotes a different line
      ml = market("moneyline", nil)
      price(ml, "home", -150)
      price(ml, "away", +130, fd)
      total = market("total", 221.5)
      price(total, "over", -108)
      price(total, "under", -112)

      lines = described_class.call(game: game)
      expect(lines.spread["home"]).to have_attributes(line: BigDecimal("-3.5"))
      expect(lines.spread["home"].price.american_odds).to eq(-105)
      expect(lines.spread["away"]).to be_nil
      expect(lines.moneyline["home"].price.american_odds).to eq(-150)
      expect(lines.moneyline["away"].price.bookmaker).to eq(fd)
      expect([ lines.total["over"].line, lines.total["under"].price.american_odds ]).to eq([ BigDecimal("221.5"), -112 ])
    end

    it "respects the enabled books" do
      ml = market("moneyline", nil)
      price(ml, "home", -150, dk)
      expect(described_class.call(game: game, bookmaker_ids: [ fd.id ]).moneyline["home"]).to be_nil
    end

    it "ignores player props and alternate lines" do
      create(:market, game: game, market_type: "player_points")
      create(:market, game: game, player: nil, market_type: "total", line: 230.5, is_alternate: true)
      expect(described_class.call(game: game).total.values).to all(be_nil)
    end
  end

  describe Games::HitStrips do
    before do
      3.times { |i| final(home, away, 100 + i, 90, 10 + i) }   # home wins by 10/11/12
      final(away, home, 105, 100, 20)                           # home loses by 5
    end

    def strips
      ml = market("moneyline", nil)
      price(ml, "home", -150)
      price(ml, "away", +130)
      sp = market("spread", -8.5)
      price(sp, "home", -110)
      tot = market("total", 195.5)
      price(tot, "over", -110)
      price(tot, "under", -110)
      lines = Games::Lines.call(game: game)
      described_class.call(game: game, lines: lines)
    end

    it "moneyline: did the team win" do
      s = strips
      expect(s[%w[moneyline home]].rate).to eq(75)
      expect(s[%w[moneyline away]].rate).to eq(25)
    end

    it "spread: would the team have covered today's number (margin + spread > 0)" do
      s = strips
      expect(s[%w[spread home]].outcomes.sort_by(&:to_s)).to eq([ false, true, true, true ].sort_by(&:to_s)) # margins 10,11,12 cover -8.5; the -5 loss does not
      expect(s[%w[spread home]].rate).to eq(75)
    end

    it "total: combined points against today's total, for over and under" do
      s = strips
      expect(s[%w[total over]].rate + s[%w[total under]].rate).to eq(100)
    end

    it "only looks at games before this one and leaves out missing cells" do
      expect(strips.keys).not_to include(%w[spread away])
    end
  end

  describe Games::Board do
    before { game }

    it "returns the day's cards with records and filters by team" do
      final(home, away, 100, 90, 3)
      cards = described_class.call(date: game.slate_date)
      expect(cards.size).to eq(1)
      expect(cards.first.home_record.to_s).to eq("1-0")
      expect(described_class.call(date: game.slate_date, query: "owls").size).to eq(1)
      expect(described_class.call(date: game.slate_date, query: "hom").size).to eq(1)
      expect(described_class.call(date: game.slate_date, query: "zzz")).to be_empty
    end

    it "is empty for a day with no games" do
      expect(described_class.call(date: game.slate_date + 3)).to be_empty
    end

    it "builds a seven day strip with counts" do
      dates = described_class.dates(today: game.slate_date)
      expect(dates.size).to eq(7)
      expect(dates.first).to eq([ game.slate_date, 1 ])
      expect(dates.last.last).to eq(0)
    end
  end

  describe Games::TeamStats do
    def log(player, team, opp, points, g)
      create(:player_game_log, player: player, game: g, team: team, opponent_team: opp, points: points, season: 2026, game_date: g.slate_date)
    end

    it "averages what a team scored and allowed per game and ranks both" do
      p1 = create(:player, sport: sport, team: home)
      p2 = create(:player, sport: sport, team: away)
      g1 = final(home, away, 0, 0, 5)
      log(p1, home, away, 100, g1)
      log(p2, away, home, 80, g1)
      stats = described_class.call(season: 2026)
      expect(stats[home.id].scored["points"]).to have_attributes(avg: 100, rank: 1)
      expect(stats[away.id].scored["points"]).to have_attributes(avg: 80, rank: 2)
      expect(stats[home.id].allowed["points"]).to have_attributes(avg: 80, rank: 1) # allowed the fewest
      expect(stats[away.id].allowed["points"]).to have_attributes(avg: 100, rank: 2)
    end

    it "sums every player in a game before averaging and ignores DNPs" do
      a, b, c = create_list(:player, 3, sport: sport, team: home)
      g1 = final(home, away, 0, 0, 5)
      [ [ a, 20 ], [ b, 30 ] ].each { |pl, pts| log(pl, home, away, pts, g1) }
      create(:player_game_log, player: c, game: g1, team: home, opponent_team: away, points: 99, minutes: 0, season: 2026, game_date: g1.slate_date)
      expect(described_class.call(season: 2026)[home.id].scored["points"].avg).to eq(50)
    end
  end
end
