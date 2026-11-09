require "rails_helper"

RSpec.describe EntityResolver do
  let(:world) { build_world }
  let(:resolver) { described_class.new(provider: "sports_game_odds", sport: world[:sport]) }

  def ref(id, name, team: nil) = Dto::PlayerRef.new(external_id: id, name: name, team: team)
  def team_ref(id, name, abbr) = Dto::TeamRef.new(external_id: id, name: name, abbreviation: abbr)

  describe "#team" do
    it "matches by abbreviation and remembers the external id" do
      team = resolver.team(team_ref("BOSTON_CELTICS_NBA", "ignored", "BOS"))
      expect(team).to eq(world[:home])
      expect(ExternalId.lookup("sports_game_odds", "team", "BOSTON_CELTICS_NBA")).to eq(world[:home])
    end

    it "falls back to the full name" do
      expect(resolver.team(team_ref("LA", "Los Angeles Lakers", nil))).to eq(world[:away])
    end

    it "prefers an exact external id over heuristics" do
      ExternalId.register!("sports_game_odds", "team", "X", world[:away])
      expect(resolver.team(team_ref("X", "Boston Celtics", "BOS"))).to eq(world[:away])
    end

    it "skips and records unknown teams instead of guessing" do
      expect(resolver.team(team_ref("NOPE", "Seattle Supersonics", "SEA"))).to be_nil
      expect(UnresolvedEntity.open.pluck(:external_type, :external_id)).to eq([ %w[team NOPE] ])
    end

    it "returns nil for a missing ref" do
      expect(resolver.team(nil)).to be_nil
    end
  end

  describe "#player" do
    {
      "accents stripped" => "Dusan Markovic",
      "accents kept" => "Dušan Marković",
      "case and spacing" => "  DUSAN   markovic "
    }.each do |label, name|
      it "matches #{label}" do
        expect(resolver.player(ref("P1", name), team: world[:home])).to eq(world[:p1])
      end
    end

    it "matches a name carrying a suffix the other provider omits (Jr.)" do
      expect(resolver.player(ref("P2", "Jaylen Brooks"), team: world[:away])).to eq(world[:p2])
    end

    it "matches hyphenated names written with a space" do
      hyphen = create(:player, sport: world[:sport], team: world[:home], first_name: "Tyrese", last_name: "Gilmore-Adeyemi")
      expect(resolver.player(ref("P3", "Tyrese Gilmore Adeyemi"), team: world[:home])).to eq(hyphen)
    end

    it "matches nicknames" do
      mike = create(:player, sport: world[:sport], team: world[:home], first_name: "Michael", last_name: "Stanhope")
      expect(resolver.player(ref("P4", "Mike Stanhope"), team: world[:home])).to eq(mike)
    end

    it "requires the team to match (same name, wrong team is not guessed)" do
      expect(resolver.player(ref("P5", "Dusan Markovic"), team: world[:away])).to be_nil
      expect(UnresolvedEntity.find_by(external_id: "P5").reason).to match(/name and team/)
    end

    it "does not guess without a team" do
      expect(resolver.player(ref("P6", "Dusan Markovic"), team: nil)).to be_nil
    end

    it "refuses ambiguous matches" do
      create(:player, sport: world[:sport], team: world[:home], first_name: "Dusan", last_name: "Markovic")
      expect(resolver.player(ref("P7", "Dusan Markovic"), team: world[:home])).to be_nil
    end

    it "marks an unresolved row resolved once it later matches" do
      resolver.player(ref("P8", "Late Arrival"), team: world[:home])
      expect(UnresolvedEntity.open.count).to eq(1)
      create(:player, sport: world[:sport], team: world[:home], first_name: "Late", last_name: "Arrival")
      resolver.player(ref("P8", "Late Arrival"), team: world[:home])
      expect(UnresolvedEntity.open.count).to eq(0)
    end
  end

  describe "#game" do
    let(:home) { team_ref("BOSTON_CELTICS_NBA", "Boston Celtics", "BOS") }
    let(:away) { team_ref("LOS_ANGELES_LAKERS_NBA", "Los Angeles Lakers", "LAL") }

    it "matches on teams and start time within 3 hours" do
      found = resolver.game(event_id: "E1", home: home, away: away, starts_at: world[:game].starts_at + 2.hours)
      expect(found).to eq(world[:game])
      expect(ExternalId.lookup("sports_game_odds", "game", "E1")).to eq(world[:game])
    end

    it "does not match when the start time is too far off" do
      expect(resolver.game(event_id: "E2", home: home, away: away, starts_at: world[:game].starts_at + 4.hours)).to be_nil
      expect(UnresolvedEntity.find_by(external_id: "E2")).to be_present
    end

    it "does not match swapped home/away" do
      expect(resolver.game(event_id: "E3", home: away, away: home, starts_at: world[:game].starts_at)).to be_nil
    end
  end
end
