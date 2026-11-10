require "rails_helper"

RSpec.describe Providers::Registry do
  it "serves every capability from the fixture provider in test" do
    %i[odds props reference stats].each { |cap| expect(described_class.for(cap)).to be_a(Providers::Fixture) }
  end

  it "never reports fixtures as live" do
    expect(described_class.for(:odds).live?).to be(false)
  end

  it "rejects unknown capabilities" do
    expect { described_class.for(:weather) }.to raise_error(ArgumentError)
  end

  it "exposes the free-tier budgets" do
    expect(described_class.budget_config("sports_game_odds")).to include(monthly_units: 2500, ceiling: 0.8)
  end

  it "builds a no-network parser for replaying payloads" do
    parser = described_class.parser("sports_game_odds", at: Time.utc(2026, 1, 1))
    expect(parser).to be_a(Providers::SportsGameOdds)
    expect { parser.transport.get("/x") }.to raise_error(/cannot fetch/)
  end

  it "builds live adapters for production config without calling the network" do
    allow(described_class).to receive(:budget_config).and_call_original
    adapter = described_class.send(:build, "sports_game_odds")
    expect(adapter.live?).to be(true)
  end

  it "switches every capability to the live adapters when LIVE_DATA=true, whatever the environment" do
    stub_const("ENV", ENV.to_h.merge("LIVE_DATA" => "true"))
    expect(described_class.for(:odds)).to be_a(Providers::SportsGameOdds)
    expect(described_class.for(:stats)).to be_a(Providers::BallDontLie)
    expect(described_class.for(:stats).live?).to be(true)
  end
end
