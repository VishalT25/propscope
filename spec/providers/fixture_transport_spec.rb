require "rails_helper"

RSpec.describe Providers::FixtureTransport do
  it "serves recorded JSON and is never metered" do
    transport = described_class.new("balldontlie", today: described_class::ANCHOR)
    expect(transport.metered?).to be(false)
    expect(transport.get("/teams")["data"].size).to eq(16)
  end

  it "shifts every date by the distance from the anchor so the slate is always today" do
    today = Date.new(2027, 1, 20)
    transport = described_class.new("balldontlie", today: today)
    games = transport.get("/games", "start_date" => today.iso8601, "end_date" => today.iso8601)["data"]
    expect(games.size).to eq(8)
    expect(games.map { |g| g["date"] }.uniq).to eq([ today.iso8601 ])
  end

  it "filters stats by date like the real API" do
    transport = described_class.new("balldontlie", today: described_class::ANCHOR)
    rows = transport.get("/stats", "dates[]" => "2026-11-08")["data"]
    expect(rows).not_to be_empty
    expect(rows.map { |r| r.dig("game", "date") }.uniq).to eq([ "2026-11-08" ])
  end

  it "raises for unknown endpoints" do
    expect { described_class.new("balldontlie").get("/nope") }.to raise_error(ArgumentError, /no fixture/)
  end
end
