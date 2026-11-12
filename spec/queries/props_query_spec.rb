require "rails_helper"

RSpec.describe PropsQuery do
  let(:dk) { create(:bookmaker, key: "dk", code: "DK") }
  let(:fd) { create(:bookmaker, key: "fd", code: "FD") }
  let(:game) { create(:game, starts_at: 5.hours.from_now, season: 2026) }

  def filters(**params) = PropsQuery::Filters.from_params(params.transform_keys(&:to_s))
  def run(**params) = described_class.call(filters: filters(**params))

  # A player prop with prices and precomputed hit rates for both sides.
  def prop(name: "Alex Smith", team: game.home_team, type: "player_points", line: 24.5, over: -110, under: -110, rates: {}, book: dk, g: game, position: "G")
    player = create(:player, sport: g.sport, team: team, first_name: name.split.first, last_name: name.split.last, position: position)
    market = create(:market, game: g, player: player, market_type: type, line: line)
    { "over" => over, "under" => under }.each do |side, price|
      create(:odds_snapshot, market: market, bookmaker: book, outcome: side, american_odds: price, decimal_odds: OddsMath.american_to_decimal(price))
      PropHitRate.create!({ market: market, side: side, line: line, computed_at: 1.minute.ago, l5: 60, l5_n: 5, l10: 70, l10_n: 10, l20: 65, l20_n: 20 }.merge(rates.fetch(side.to_sym, {})))
    end
    market
  end

  it "returns one row per market side with best price, implied probability and hit rates" do
    prop(over: -110, under: +100)
    rows = run.rows
    expect(rows.size).to eq(2)
    over = rows.find { |r| r.side == "over" }
    expect(over).to have_attributes(line: BigDecimal("24.5"))
    expect(over.price.american_odds).to eq(-110)
    expect(over.implied).to eq(BigDecimal("0.52381"))
    expect(over.rate("l10")).to eq(70)
    expect(over.team).to eq(game.home_team)
  end

  it "only shows props for games that have not started, and skips game-level markets" do
    prop
    started = create(:game, starts_at: 1.hour.ago)
    prop(g: started, team: started.home_team, name: "Old Game")
    create(:market, game: game, player: nil, market_type: "moneyline", line: nil)
    expect(run.rows.map { |r| r.player.last_name }.uniq).to eq([ "Smith" ])
  end

  it "skips sides with no price from the enabled books" do
    prop(book: dk)
    expect(described_class.call(filters: filters, bookmaker_ids: [ fd.id ]).total).to eq(0)
    expect(described_class.call(filters: filters, bookmaker_ids: [ dk.id ]).total).to eq(2)
  end

  describe "filters" do
    before do
      prop(name: "Alex Smith", type: "player_points", over: -150, under: +120, rates: { over: { l10: 90 } })
      prop(name: "Dušan Marković", type: "player_assists", line: 6.5, over: +130, under: -160, rates: { over: { l10: 40 } })
    end

    it "by market type" do
      expect(run(market_types: [ "player_assists" ]).rows.map { |r| r.market.market_type }.uniq).to eq([ "player_assists" ])
    end

    it "by player name, ignoring accents and case" do
      expect(run(q: "dusan").rows.map { |r| r.player.last_name }.uniq).to eq([ "Marković" ])
      expect(run(q: "SMITH").total).to eq(2)
    end

    it "by side" do
      expect(run(side: "under").rows.map(&:side).uniq).to eq([ "under" ])
    end

    it "by game" do
      other = create(:game, starts_at: 6.hours.from_now)
      prop(g: other, team: other.home_team, name: "Other Guy")
      expect(run(game_ids: [ other.id ]).rows.map { |r| r.player.last_name }.uniq).to eq([ "Guy" ])
    end

    it "by American odds range, spanning plus and minus money" do
      prices = run(odds_min: -160, odds_max: -100).rows.map { |r| r.price.american_odds }
      expect(prices).to all(be <= -100)
      expect(prices).to contain_exactly(-150, -160)
      expect(run(odds_min: 100).rows.map { |r| r.price.american_odds }).to all(be >= 100)
    end

    it "by minimum hit rate in the chosen window, requiring a real sample" do
      expect(run(min_hit_rate: 85, hit_window: "l10").rows.map { |r| [ r.player.last_name, r.side ] }).to eq([ [ "Smith", "over" ] ])
      create(:player_game_log) # unrelated
      thin = prop(name: "Thin Sample", rates: { over: { l5: 100, l5_n: 2 } })
      expect(run(min_hit_rate: 90, hit_window: "l5").rows.map { |r| r.player.last_name }).not_to include("Sample")
      expect(thin).to be_present
    end

    it "lets head-to-head filter on a single game, unlike the other windows" do
      prop(name: "One Meeting", rates: { over: { h2h: 100, h2h_n: 1 } })
      expect(run(min_hit_rate: 90, hit_window: "h2h").rows.map { |r| r.player.last_name }).to include("Meeting")
    end

    it "by opponent tier from the bet's side (an under flips the tier)" do
      player = Player.find_by(last_name: "Smith")
      opponent = game.away_team
      DefenseRank.create!(team: opponent, stat: "points", position: "all", avg_allowed: 30, rank: 15, tier: "favorable", season: 2026, computed_at: Time.current)
      fav = run(tier: "favorable").rows
      expect(fav.map { |r| [ r.player, r.side ] }).to eq([ [ player, "over" ] ])
      expect(run(tier: "unfavorable").rows.map { |r| [ r.player, r.side ] }).to eq([ [ player, "under" ] ])
    end

    it "by book within the enabled books" do
      prop(name: "Fan Duel", book: fd)
      expect(run(book_keys: [ "fd" ]).rows.map { |r| r.player.last_name }.uniq).to eq([ "Duel" ])
    end

    it "hides alternate lines unless asked" do
      alt = create(:market, game: game, player: Player.find_by(last_name: "Smith"), line: 29.5, is_alternate: true)
      create(:odds_snapshot, market: alt, bookmaker: dk)
      expect(run.rows.map { |r| r.market.id }).not_to include(alt.id)
      expect(run(alt: "1").rows.map { |r| r.market.id }).to include(alt.id)
    end

    it "clamps an out-of-range hit rate to 100" do
      expect(filters(min_hit_rate: "999").min_hit_rate).to eq(100)
    end

    it "ignores invalid input instead of failing" do
      expect(run(market_types: [ "bogus" ], side: "sideways", odds_min: "abc", min_hit_rate: "abc", tier: "weird", sort: "evil", dir: "up", page: "-4").total).to be > 0
    end
  end

  describe "sorting" do
    before do
      prop(name: "Low Rate", rates: { over: { l10: 20 }, under: { l10: 25 } }, over: +150, line: 10.5)
      prop(name: "High Rate", rates: { over: { l10: 95 }, under: { l10: 90 } }, over: -200, line: 30.5)
      prop(name: "No Sample", rates: { over: { l10: 100, l10_n: 1 }, under: { l10: 100, l10_n: 1 } }, line: 20.5)
    end

    def order(**o) = run(side: "over", **o).rows.map { |r| r.player.last_name }

    it "sorts by a hit-rate window, both directions, with thin samples last" do
      expect(order(sort: "l10", dir: "desc")).to eq(%w[Rate Rate Sample])
      expect(run(side: "over", sort: "l10", dir: "desc").rows.map { |r| r.rate("l10") }.first(2)).to eq([ 95, 20 ])
      expect(run(side: "over", sort: "l10", dir: "asc").rows.map { |r| r.rate("l10") }.first(2)).to eq([ 20, 95 ])
      expect(run(side: "over", sort: "l10", dir: "desc").rows.last.player.last_name).to eq("Sample")
    end

    it "sorts by line and by best odds" do
      expect(run(side: "over", sort: "line", dir: "asc").rows.map(&:line)).to eq([ 10.5, 20.5, 30.5 ].map { |l| BigDecimal(l.to_s) })
      expect(run(side: "over", sort: "best_odds", dir: "desc").rows.first.price.american_odds).to eq(150)
    end

    it "sorts by implied probability" do
      expect(run(side: "over", sort: "ip", dir: "desc").rows.first.price.american_odds).to eq(-200)
    end
  end

  describe "pagination" do
    it "pages at 50 rows and reports totals" do
      30.times { |i| prop(name: "Player#{i} Last#{i}") }
      page1 = run(side: "over", sort: "line")
      expect([ page1.total, page1.pages, page1.rows.size ]).to eq([ 30, 1, 30 ])
      30.times { |i| prop(name: "More#{i} Guy#{i}") }
      expect(run(side: "over", page: 2).rows.size).to eq(10)
      expect(run(side: "over", page: 99).page).to eq(2)
    end

    it "returns every row when pagination is off (for the live count)" do
      60.times { |i| prop(name: "P#{i} L#{i}") }
      expect(described_class.call(filters: filters(side: "over"), paginate: false).rows.size).to eq(60)
    end
  end

  it "reports when the data was last computed" do
    prop
    expect(run.updated_at).to be_within(2.minutes).of(1.minute.ago)
  end

  it "counts only real filters as active (not sort or page)" do
    expect(filters(sort: "l5", page: 3).active_count).to eq(0)
    expect(filters(side: "over", q: "x", odds_min: -200, odds_max: 100, alt: "1").active_count).to eq(4)
  end

  it "round-trips filters through to_query for shareable links" do
    f = filters(game_ids: [ "1", "2" ], market_types: [ "player_points" ], side: "over", min_hit_rate: "70", hit_window: "l5", sort: "l5", dir: "asc")
    expect(filters(**f.to_query)).to eq(f)
  end

  describe "only EV+" do
    let(:mgm) { create(:bookmaker, key: "mgm", code: "MGM") }

    def quote(market, book, outcome, american)
      create(:odds_snapshot, market: market, bookmaker: book, outcome: outcome, american_odds: american, decimal_odds: OddsMath.american_to_decimal(american), line: market.line)
    end

    # Three books quote the market; one hangs a long over, so the best over price beats the books' consensus.
    def edge_case(name: "Edge Case")
      market = prop(name: name, over: -110, under: -110, book: dk)
      quote(market, fd, "over", -110)
      quote(market, fd, "under", -110)
      quote(market, mgm, "over", 130)
      quote(market, mgm, "under", -170)
      market
    end

    def ev_page_rows(**params) = Ev::Opportunities.call(filters: Ev::Opportunities::Filters.from_params(params), paginate: false).rows

    it "keeps the props whose best price beats the fair price, with the edge on the row" do
      edge_case
      prop(name: "Fair Game", over: -110, under: -110) # one book: no consensus, so no edge to speak of
      rows = run(ev: "1").rows
      expect(rows.map { |r| r.player.last_name }.uniq).to eq([ "Case" ])
      over = rows.find { |r| r.side == "over" }
      expect(over.ev).to be > BigDecimal("0.05")
      expect(over.price.american_odds).to eq(130)
      expect(run.rows.map(&:ev).uniq).to eq([ nil ]) # without the filter there is no edge to show
    end

    it "is exactly what the EV+ page lists, so the two can never disagree" do
      edge_case
      edge_case(name: "Second Edge")
      prop(name: "Fair Game", over: -110, under: -110)
      explorer = run(ev: "1").rows.map { |r| [ r.market.id, r.side ] }
      ev_page = ev_page_rows.map { |r| [ r.market.id, r.outcome ] }
      expect(explorer).to match_array(ev_page)
      expect(explorer).not_to be_empty
    end

    it "uses only the books the viewer has enabled for the price, but all of them for the fair price" do
      edge_case
      expect(described_class.call(filters: filters(ev: "1"), bookmaker_ids: [ dk.id, fd.id, mgm.id ]).rows).not_to be_empty
      without_mgm = described_class.call(filters: filters(ev: "1"), bookmaker_ids: [ dk.id, fd.id ]).rows
      expect(without_mgm.select { |r| r.side == "over" }).to be_empty # the +130 is no longer on offer to this viewer
    end

    it "combines with the other filters" do
      edge_case
      expect(run(ev: "1", side: "under").rows.map(&:side).uniq).to all(eq("under"))
      expect(run(ev: "1", side: "over", market_types: [ "player_rebounds" ]).rows).to be_empty
      expect(run(ev: "1", side: "over", odds_min: "120").rows.size).to eq(1)
      expect(run(ev: "1", side: "over", odds_max: "100").rows).to be_empty
    end

    it "is a filter like the others: parsed, counted, and kept in shareable links" do
      expect(filters.ev).to be(false)
      f = filters(ev: "1", min_hit_rate: "60")
      expect([ f.ev, f.active_count, f.to_query[:ev] ]).to eq([ true, 2, "1" ])
      expect(filters(**f.to_query)).to eq(f)
      expect(filters(ev: "yes").ev).to be(false) # only "1" turns it on
    end
  end
end
