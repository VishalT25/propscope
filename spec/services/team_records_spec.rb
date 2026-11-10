require "rails_helper"

RSpec.describe TeamRecords do
  let(:sport) { create(:sport) }
  let(:a) { create(:team, sport: sport) }
  let(:b) { create(:team, sport: sport) }

  def final(home, away, hs, as, days_ago)
    create(:game, sport: sport, home_team: home, away_team: away, home_score: hs, away_score: as, status: "final", season: 2026, starts_at: days_ago.days.ago)
  end

  before { final(a, b, 100, 90, 10); final(b, a, 95, 99, 8); final(a, b, 80, 85, 6); final(b, a, 70, 60, 4) }

  it "counts wins and losses overall and by venue" do
    r = described_class.call(season: 2026)
    expect(r.record(a.id).to_s).to eq("2-2")
    expect(r.record(a.id, venue: :home).to_s).to eq("1-1")
    expect(r.record(b.id, venue: :home).to_s).to eq("1-1")
  end

  it "only counts games before a date" do
    r = described_class.call(season: 2026)
    expect(r.record(a.id, before: 7.days.ago.to_date).to_s).to eq("2-0")
  end

  it "returns no percentage until a team has played enough games to mean anything" do
    r = described_class.call(season: 2026)
    expect(r.pct_before(a.id, 9.days.ago.to_date)).to be_nil
    expect(r.pct_before(a.id, 2.days.ago.to_date)).to eq(BigDecimal("0.5"))
  end

  it "ignores games without a final score and other seasons" do
    create(:game, sport: sport, home_team: a, away_team: b, status: "scheduled", season: 2026, starts_at: 1.day.from_now)
    create(:game, sport: sport, home_team: a, away_team: b, home_score: 1, away_score: 0, status: "final", season: 2025, starts_at: 400.days.ago)
    expect(described_class.call(season: 2026).record(a.id).to_s).to eq("2-2")
  end

  it "reports recent form, newest last" do
    expect(described_class.call(season: 2026).last(a.id, 3)).to eq([ true, false, false ])
  end
end
