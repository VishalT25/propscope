require "rails_helper"

RSpec.describe ModelFeatures do
  let(:stat) { StatCatalog.for_market("player_points") }
  let(:sport) { create(:sport) }
  let(:home) { create(:team, sport: sport) }
  let(:away) { create(:team, sport: sport) }
  let(:player) { create(:player, sport: sport, team: home) }
  let(:teammate) { create(:player, sport: sport, team: home) }
  let(:rival) { create(:player, sport: sport, team: away) }

  # `points` scored by player (and the teams' totals) on day D
  def played(day, points, minutes: 30, home_game: true, opp: away, stats: {})
    date = Date.new(2026, 11, 1) + day
    g = create(:game, sport: sport, home_team: home_game ? home : opp, away_team: home_game ? opp : home, starts_at: date.in_time_zone("America/New_York").change(hour: 19), season: 2026)
    create(:player_game_log, player: player, game: g, team: home, opponent_team: opp, points: points, minutes: minutes, home: home_game, game_date: date, season: 2026, stats: stats)
    create(:player_game_log, player: rival, game: g, team: opp, opponent_team: home, points: 100, minutes: 30, home: !home_game, game_date: date, season: 2026)
    create(:player_game_log, player: teammate, game: g, team: home, opponent_team: opp, points: 70, minutes: 30, home: home_game, game_date: date, season: 2026)
    g
  end

  def features(on:, **o) = described_class.new(stat: stat).features_for(player_id: player.id, team_id: home.id, opponent_id: away.id, date: Date.new(2026, 11, 1) + on, season: 2026, home: true, **o)

  it "uses only games before the date and exposes exactly the contract's feature names" do
    (0..5).each { |d| played(d, 10 + d) }       # 10, 11, 12, 13, 14, 15
    played(6, 99)                                # the game being predicted: must not leak in
    f = features(on: 6)
    expect(f.keys).to eq(ModelFeatures::FEATURES)
    expect(f["mean_l5"]).to eq(BigDecimal("13") .to_f) # 11..15
    expect(f["mean_l10"]).to eq(12.5)
    expect(f["games_played"]).to eq(6.0)
    expect(f.values_at("mean_l5", "mean_l10", "mean_l20", "mean_season", "std_l10").max).to be < 99 # the 99-point game never leaks into the player's own stats
  end

  it "needs enough history" do
    (0..3).each { |d| played(d, 10) }
    expect(features(on: 4)).to be_nil
  end

  it "ignores DNPs" do
    (0..5).each { |d| played(d, 10) }
    played(6, 0, minutes: 0)
    expect(features(on: 7)["games_played"]).to eq(6.0)
  end

  it "computes rest days and back-to-backs" do
    (0..5).each { |d| played(d, 10) }
    expect([ features(on: 6)["rest_days"], features(on: 6)["back_to_back"] ]).to eq([ 1.0, 1.0 ])
    expect([ features(on: 9)["rest_days"], features(on: 9)["back_to_back"] ]).to eq([ 4.0, 0.0 ])
    expect(features(on: 60)["rest_days"]).to eq(14.0) # capped
  end

  it "reads shot volume from the stored box score and tolerates a missing key" do
    (0..5).each { |d| played(d, 10, stats: { "fga" => 10 + d, "fta" => 4 }) }
    f = features(on: 6)
    expect(f["fga_l10"]).to eq(12.5)
    expect(f["fta_l10"]).to eq(4.0)
    expect(f["fg3a_l10"]).to be_nil
  end

  it "describes the team scoring environment from box scores, before the date only" do
    (0..5).each { |d| played(d, 10) }              # team (player + teammate) scores 80, opponent 100
    f = features(on: 6)
    expect([ f["team_scored_l10"], f["opp_scored_l10"], f["opp_allowed_l10"] ]).to eq([ 80.0, 100.0, 80.0 ])
  end

  it "builds one training row per game with prior history, target = the stat, never using that game" do
    (0..7).each { |d| played(d, 10 + d) }
    rows = described_class.new(stat: stat).training_rows.select { |r| r.player_id == player.id }
    expect(rows.size).to eq(3) # games 5, 6, 7 have at least 5 prior games
    last = rows.max_by(&:game_date)
    expect(last.target).to eq(17)
    expect(last.features["mean_l5"]).to eq(14.0) # games 2..6 = 12..16, not including the 17
  end

  it "matches the Python service's feature list (they must not drift)" do
    python = File.read(Rails.root.join("model_service/app/features.py"))
    names = python[/FEATURES = \[(.*?)\]/m, 1].scan(/"([a-z0-9_]+)"/).flatten
    expect(names).to eq(ModelFeatures::FEATURES)
  end
end
