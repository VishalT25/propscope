require "rails_helper"

RSpec.describe PredictPropsJob do
  let(:sport) { create(:sport) }
  let(:home) { create(:team, sport: sport) }
  let(:away) { create(:team, sport: sport) }
  let(:game) { create(:game, sport: sport, home_team: home, away_team: away, starts_at: 6.hours.from_now, season: 2026) }
  let(:player) { create(:player, sport: sport, team: home) }
  let!(:market) { create(:market, game: game, player: player, market_type: "player_points", line: 24.5) }
  let(:client) { instance_double(ModelClient, enabled?: true) }

  def history(n = 8)
    n.times do |i|
      g = create(:game, sport: sport, home_team: home, away_team: away, starts_at: (i + 2).days.ago, season: 2026)
      create(:player_game_log, player: player, game: g, team: home, opponent_team: away, points: 20 + i, game_date: g.starts_at.to_date, season: 2026)
    end
  end

  def response_for(id) = { model_version: "v1", predictions: [ { "id" => id.to_s, "projection" => 23.4, "p_over" => 0.4, "p_under" => 0.6, "p_push" => 0.0 } ] }

  it "stores a prediction for each side of upcoming points props" do
    history
    allow(client).to receive(:predict) { response_for(market.id) }
    described_class.perform_now(client: client)
    over, under = %w[over under].map { |s| Prediction.find_by(market: market, side: s) }
    expect(over).to have_attributes(probability: BigDecimal("0.4"), projection: BigDecimal("23.4"), model_version: "v1")
    expect(under.probability).to eq(BigDecimal("0.6"))
  end

  it "sends features and the line, and only for props that have enough history" do
    history
    other = create(:market, game: game, player: create(:player, sport: sport, team: home), market_type: "player_points", line: 9.5) # no history
    sent = nil
    allow(client).to receive(:predict) { |rows| sent = rows; response_for(market.id) }
    described_class.perform_now(client: client)
    expect(sent.map { |r| r[:id] }).to eq([ market.id.to_s ])
    expect(sent.first[:line]).to eq(24.5)
    expect(sent.first[:features].keys).to eq(ModelFeatures::FEATURES)
    expect(Prediction.where(market: other)).to be_empty
  end

  it "is idempotent: a second run updates in place" do
    history
    allow(client).to receive(:predict) { response_for(market.id) }
    described_class.perform_now(client: client)
    expect { described_class.perform_now(client: client) }.not_to change(Prediction, :count)
  end

  it "does nothing when the service is not configured" do
    off = instance_double(ModelClient, enabled?: false)
    expect(off).not_to receive(:predict)
    described_class.perform_now(client: off)
    expect(Prediction.count).to eq(0)
  end

  it "does not fail the job when the service is down: no predictions, no error" do
    history
    allow(client).to receive(:predict).and_raise(ModelClient::Unavailable, "boom")
    expect { described_class.perform_now(client: client) }.not_to raise_error
    expect(Prediction.count).to eq(0)
  end

  it "keeps the last good predictions when the service later goes down" do
    history
    allow(client).to receive(:predict) { response_for(market.id) }
    described_class.perform_now(client: client)
    allow(client).to receive(:predict).and_raise(ModelClient::Unavailable)
    described_class.perform_now(client: client)
    expect(Prediction.count).to eq(2)
  end

  it "ignores started games and alternate lines" do
    history
    market.update!(is_alternate: true)
    expect(client).not_to receive(:predict)
    described_class.perform_now(client: client)
  end

  it "runs from the precompute chain without needing the service" do
    expect { PrecomputeHitRatesJob.perform_now }.not_to raise_error
    expect(Prediction.count).to eq(0)
  end
end
