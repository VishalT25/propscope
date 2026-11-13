require "rails_helper"

# Contract tests against synthetic samples shaped like BallDontLie responses (invented players and ids, no recorded provider data).
RSpec.describe "BallDontLie real response shape" do
  let(:provider) { Providers::BallDontLie.new(transport: Providers::NullTransport.new) }
  let(:stats) { JSON.parse(Rails.root.join("spec/fixtures/providers/balldontlie/synthetic_shape_stats_sample.json").read) }
  let(:players) { JSON.parse(Rails.root.join("spec/fixtures/providers/balldontlie/synthetic_shape_players_sample.json").read) }

  it "maps a real box-score row" do
    log = provider.parse_game_logs(stats).first
    expect(log).to have_attributes(provider: "balldontlie", points: 11, rebounds: 4, assists: 4, threes_made: 3, steals: 2, fouls: 0)
    expect(log.minutes).to eq(BigDecimal("32.78")) # "32:47"
    expect(log.game_date).to eq(Date.new(2026, 11, 9))
    expect(log.stats).to include("fga" => 9, "fg3a" => 6)
  end

  it "derives home flag and opponent from the nested game" do
    log = provider.parse_game_logs(stats).first
    game = stats["data"].first["game"]
    expect(log.home).to eq(stats["data"].first["team"]["id"] == game["home_team_id"])
    opponent = log.home ? game["visitor_team_id"] : game["home_team_id"]
    expect(log.opponent_team_external_id).to eq(opponent.to_s)
  end

  it "treats a '00' minutes line as a DNP" do
    expect(provider.parse_game_logs(stats).last.minutes).to eq(0)
  end

  it "maps /players/active with team refs" do
    player = provider.parse_players(players).first
    expect(player).to have_attributes(provider: "balldontlie", first_name: "Warren", last_name: "Pellegrini", position: "C")
    expect(player.team).to have_attributes(abbreviation: "HOU", name: "Houston Rockets")
  end
end
