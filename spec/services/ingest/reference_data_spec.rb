require "rails_helper"

RSpec.describe Ingest::ReferenceData do
  let(:provider) { Providers::Fixture.new(today: Providers::FixtureTransport::ANCHOR) }
  let(:today) { Providers::FixtureTransport::ANCHOR }

  def run
    described_class.call(teams: provider.fetch_teams(sport: "nba"), players: provider.fetch_players(sport: "nba"))
    described_class.call(events: provider.fetch_events(sport: "nba", from: today - 5, to: today + 1))
  end

  it "creates canonical teams, players and games" do
    run
    expect([ Team.count, Player.count ]).to eq([ 16, 96 ])
    expect(Game.where(slate_date: today).count).to eq(8)
    expect(Player.find_by(last_name: "Marković").normalized_name).to eq("dusan markovic")
    expect(Player.where.not(team: nil).count).to eq(96)
  end

  it "is idempotent: running twice creates no duplicates" do
    run
    counts = [ Team, Player, Game, ExternalId ].map(&:count)
    run
    expect([ Team, Player, Game, ExternalId ].map(&:count)).to eq(counts)
  end

  it "updates scores and status when a game finishes" do
    run
    game = Game.where(slate_date: today).first
    ext = ExternalId.find_by(internal: game, external_type: "game")
    dto = provider.fetch_events(sport: "nba", from: today, to: today).find { |e| e.external_id == ext.external_id }
    final = dto.with(status: "final", home_score: 110, away_score: 104)
    described_class.call(events: [ final ])
    expect(game.reload).to have_attributes(status: "final", home_score: 110, away_score: 104)
    expect(Game.count).to eq(Game.distinct.count(:id))
  end

  it "stores the slate date as the US Eastern date, not the UTC date" do
    run
    late = Game.where(slate_date: today).order(:starts_at).last
    expect(late.starts_at.utc.to_date).to be >= today
    expect(late.slate_date).to eq(late.starts_at.in_time_zone("America/New_York").to_date)
  end

  it "counts games it cannot place (unknown teams) as skipped" do
    dto = provider.fetch_events(sport: "nba", from: today, to: today).first
    result = described_class.call(events: [ dto ])
    expect(result.games).to eq(0)
    expect(result.skipped).to eq(1)
  end

  it "keeps a player's team when they move (trade) by following the provider id" do
    run
    player = Player.find_by(last_name: "Marković")
    new_team = Team.where.not(id: player.team_id).first
    new_ext = ExternalId.find_by(internal: new_team, external_type: "team").external_id
    dto = provider.fetch_players(sport: "nba").find { |p| p.last_name == "Marković" }
    described_class.call(players: [ dto.with(team: dto.team.with(external_id: new_ext)) ])
    expect(player.reload.team).to eq(new_team)
    expect(Player.count).to eq(96)
  end
end
