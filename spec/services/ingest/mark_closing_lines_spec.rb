require "rails_helper"

RSpec.describe Ingest::MarkClosingLines do
  let(:game) { create(:game, starts_at: Time.utc(2026, 11, 10, 0, 0)) }
  let(:market) { create(:market, game: game, player: create(:player, team: game.home_team, sport: game.sport)) }
  let(:book) { create(:bookmaker) }

  def snap(price, at, outcome: "over", bookmaker: book)
    create(:odds_snapshot, market: market, bookmaker: bookmaker, outcome: outcome, american_odds: price, captured_at: at)
  end

  it "marks the last snapshot at or before tip as closing, per outcome and book" do
    early = snap(-110, game.starts_at - 5.hours)
    last_pre = snap(-130, game.starts_at - 10.minutes)
    at_tip = snap(-135, game.starts_at)
    live = snap(-300, game.starts_at + 30.minutes)
    under = snap(100, game.starts_at - 1.hour, outcome: "under")
    other = snap(-105, game.starts_at - 2.hours, bookmaker: create(:bookmaker))

    described_class.call(now: game.starts_at + 1.hour)
    expect([ early, last_pre, at_tip, live, under, other ].map { |s| s.reload.is_closing }).to eq([ false, false, true, false, true, true ])
  end

  it "does nothing before tip-off" do
    snap(-110, game.starts_at - 1.hour)
    described_class.call(now: game.starts_at - 1.minute)
    expect(OddsSnapshot.where(is_closing: true)).to be_empty
  end

  it "is idempotent" do
    snap(-110, game.starts_at - 1.hour)
    described_class.call(now: game.starts_at + 1.minute)
    expect { described_class.call(now: game.starts_at + 2.minutes) }.not_to change { OddsSnapshot.where(is_closing: true).count }
  end

  it "ignores games that started more than 48h ago" do
    snap(-110, game.starts_at - 1.hour)
    described_class.call(now: game.starts_at + 3.days)
    expect(OddsSnapshot.where(is_closing: true)).to be_empty
  end
end
