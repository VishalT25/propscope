require "rails_helper"

RSpec.describe "Model column (optional model service)" do
  seed_fixtures_once

  let(:market) { Market.joins(:game).where("games.starts_at > now()").where(market_type: "player_points").first }

  it "does not show a Model column or line when there are no predictions (service off)" do
    get "/nba/props"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Model: chance this side wins")
    get "/nba/props/#{market.id}/over"
    expect(response.body).not_to include("model chance of the over")
  end

  it "shows the column, tooltip and detail line once predictions exist, and the explorer sorts by it" do
    Market.joins(:game).where("games.starts_at > now()").where(market_type: "player_points").limit(5).each_with_index do |m, i|
      %w[over under].each { |s| Prediction.create!(market: m, side: s, probability: s == "over" ? 0.5 + i * 0.08 : 0.5 - i * 0.08, projection: 20 + i, model_version: "test-1", computed_at: Time.current) }
    end
    get "/nba/props", params: { market_types: [ "player_points" ], side: "over", sort: "model", dir: "desc" }
    expect(response.body).to include("Model: chance this side wins", "Model (test-1) projects")
    pcts = response.body.scan(/title="Model \(test-1\) projects[^>]*>(\d+)%/).flatten.map(&:to_i)
    expect(pcts).to eq(pcts.sort.reverse)
    get "/nba/props/#{market.id}/over"
    expect(response.body).to match(/model chance of the over/)
  end

  it "keeps working when the service is down (the prediction job fails soft)" do
    down = instance_double(ModelClient, enabled?: true)
    allow(down).to receive(:predict).and_raise(ModelClient::Unavailable)
    expect { PredictPropsJob.perform_now(client: down) }.not_to raise_error
    get "/nba/props"
    expect(response).to have_http_status(:ok)
    get "/nba/ev"
    expect(response).to have_http_status(:ok)
  end
end

RSpec.describe Prediction do
  it "validates side and a probability strictly between 0 and 1" do
    base = { market: create(:market), side: "over", probability: 0.5, model_version: "v", computed_at: Time.current }
    expect(described_class.new(base)).to be_valid
    expect(described_class.new(base.merge(side: "middle"))).not_to be_valid
    expect(described_class.new(base.merge(probability: 1))).not_to be_valid
    expect(described_class.new(base.merge(probability: 0))).not_to be_valid
  end
end
