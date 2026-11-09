require "rails_helper"

RSpec.describe HitRates::Precompute do
  let(:game) { create(:game, starts_at: 5.hours.from_now, season: 2026) }
  let(:player) { create(:player, team: game.home_team, sport: game.sport) }
  let!(:market) { create(:market, game: game, player: player, market_type: "player_points", line: 20.5) }

  def log(points, days_ago:, opponent: game.away_team, minutes: 30, season: 2026)
    past = create(:game, sport: game.sport, home_team: game.home_team, away_team: opponent, starts_at: days_ago.days.ago, season: season)
    create(:player_game_log, player: player, game: past, team: game.home_team, opponent_team: opponent, points: points,
                             minutes: minutes, game_date: past.starts_at.to_date, season: season)
  end

  it "writes both sides with windows, sample sizes, mean and median" do
    [ 25, 30, 10, 22, 18, 24 ].each_with_index { |pts, i| log(pts, days_ago: i + 2) }
    expect(described_class.call).to eq(2)
    over = PropHitRate.find_by(market: market, side: "over")
    under = PropHitRate.find_by(market: market, side: "under")
    expect(over).to have_attributes(l5_n: 5, l10_n: 6, season_n: 6, prev_season_n: 0, h2h_n: 6, line: BigDecimal("20.5"))
    expect(over.l5).to eq(60)
    expect(under.l5).to eq(40)
    expect(over.l10).to eq(BigDecimal("66.67"))
    expect(over.mean).to eq(BigDecimal("21.5"))
    expect(over.prev_season).to be_nil
  end

  it "is idempotent" do
    log(25, days_ago: 2)
    described_class.call
    expect { described_class.call }.not_to change(PropHitRate, :count)
  end

  it "recomputes in place when new games arrive" do
    log(25, days_ago: 3)
    described_class.call
    log(5, days_ago: 2)
    described_class.call
    expect(PropHitRate.find_by(market: market, side: "over").l5).to eq(50)
  end

  it "skips DNPs and handles a player with no logs" do
    log(30, days_ago: 2, minutes: 0)
    described_class.call
    expect(PropHitRate.find_by(market: market, side: "over")).to have_attributes(l5: nil, l5_n: 0, mean: nil)
  end

  it "uses the opponent for H2H, including the previous season" do
    log(25, days_ago: 10, opponent: game.away_team)
    log(10, days_ago: 4, opponent: create(:team, sport: game.sport))
    log(25, days_ago: 300, opponent: game.away_team, season: 2025)
    described_class.call
    expect(PropHitRate.find_by(market: market, side: "over")).to have_attributes(h2h_n: 2, h2h: 100, prev_season_n: 1)
  end

  it "ignores game-level markets, started games and players whose team is not in the game" do
    create(:market, game: game, player: nil, market_type: "moneyline", line: nil)
    started = create(:game, starts_at: 1.hour.ago)
    create(:market, game: started, player: create(:player, team: started.home_team, sport: started.sport))
    stranger = create(:player, sport: game.sport)
    create(:market, game: game, player: stranger, line: 9.5)
    expect(described_class.call).to eq(2)
  end

  describe "closing line hit rate" do
    it "scores past games against that game's own closing line" do
      past = log(25, days_ago: 2)
      other = log(15, days_ago: 3)
      [ [ past.game, 24.5 ], [ other.game, 14.5 ] ].each do |g, line|
        m = create(:market, game: g, player: player, market_type: "player_points", line: line)
        create(:odds_snapshot, market: m, is_closing: true, captured_at: g.starts_at - 5.minutes)
      end
      described_class.call
      expect(PropHitRate.find_by(market: market, side: "over").closing_line_hit_rate).to eq(100)
      expect(PropHitRate.find_by(market: market, side: "under").closing_line_hit_rate).to eq(0)
    end

    it "is nil when no past closing lines exist" do
      log(25, days_ago: 2)
      described_class.call
      expect(PropHitRate.find_by(market: market, side: "over").closing_line_hit_rate).to be_nil
    end
  end
end
