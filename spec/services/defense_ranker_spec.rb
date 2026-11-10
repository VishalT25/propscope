require "rails_helper"

RSpec.describe DefenseRanker do
  let(:sport) { create(:sport) }
  let!(:teams) { create_list(:team, 6, sport: sport) }
  let(:shooter_team) { create(:team, sport: sport) }

  # one guard on shooter_team scores `points` against each team
  def seed_logs(points_by_team, position: "G", season: 2026)
    player = create(:player, sport: sport, team: shooter_team, position: position)
    points_by_team.each_with_index do |(team, pts), i|
      game = create(:game, sport: sport, home_team: shooter_team, away_team: team, season: season, starts_at: (i + 1).days.ago)
      create(:player_game_log, player: player, game: game, team: shooter_team, opponent_team: team, points: pts, season: season, game_date: game.starts_at.to_date)
    end
  end

  it "ranks by average allowed ascending (rank 1 = toughest) and tiers them" do
    seed_logs(teams.each_with_index.to_h { |t, i| [ t, 10 + i * 5 ] }) # teams[0] allows 10, teams[5] allows 35
    rows = described_class.call(season: 2026, tier_size: 2).select { |r| r.stat == "points" && r.position == "G" }.sort_by(&:rank)
    expect(rows.map(&:team_id)).to eq(teams.map(&:id))
    expect(rows.map(&:tier)).to eq(%w[unfavorable unfavorable neutral neutral favorable favorable])
    expect(rows.first.avg_allowed).to eq(10)
  end

  it "persists to defense_ranks and is idempotent" do
    seed_logs(teams.to_h { |t| [ t, 20 ] })
    described_class.call(season: 2026, tier_size: 2)
    expect { described_class.call(season: 2026, tier_size: 2) }.not_to change(DefenseRank, :count)
    expect(DefenseRank.first.computed_at).to be_present
  end

  it "caps tier size at a third of the league so a small league keeps a neutral middle" do
    seed_logs(teams.each_with_index.to_h { |t, i| [ t, 10 + i ] })
    tiers = described_class.call(season: 2026, tier_size: 10).select { |r| r.stat == "points" && r.position == "G" }.map(&:tier)
    expect(tiers.tally).to eq("unfavorable" => 2, "neutral" => 2, "favorable" => 2)
  end

  it "keeps positions separate and buckets hybrids like G-F under G" do
    seed_logs(teams.to_h { |t| [ t, 20 ] }, position: "G-F")
    expect(described_class.call(season: 2026, tier_size: 2).map(&:position).uniq).to match_array(%w[G all])
  end

  it "ignores DNPs, other seasons and players without a position" do
    seed_logs({ teams[0] => 30 }, position: "G")
    PlayerGameLog.update_all(minutes: 0)
    expect(described_class.call(season: 2026)).to be_empty
    PlayerGameLog.update_all(minutes: 30)
    expect(described_class.call(season: 2025)).to be_empty
    Player.update_all(position: nil)
    expect(described_class.call(season: 2026).map(&:position).uniq).to eq([ "all" ]) # only the all-positions rollup remains
  end

  it "averages per game across the whole position group, not per player" do
    team = teams.first
    g1 = create(:player, sport: sport, team: shooter_team, position: "G")
    g2 = create(:player, sport: sport, team: shooter_team, position: "G")
    game = create(:game, sport: sport, home_team: shooter_team, away_team: team, season: 2026, starts_at: 1.day.ago)
    [ g1, g2 ].each { |p| create(:player_game_log, player: p, game: game, team: shooter_team, opponent_team: team, points: 15, season: 2026) }
    row = described_class.call(season: 2026).find { |r| r.team_id == team.id && r.stat == "points" && r.position == "G" }
    expect(row.avg_allowed).to eq(30)
  end

  it "covers every stat including PRA" do
    seed_logs({ teams[0] => 30 })
    expect(described_class.call(season: 2026).map(&:stat).uniq).to match_array(StatCatalog::DEFENSE_STATS)
  end
end
