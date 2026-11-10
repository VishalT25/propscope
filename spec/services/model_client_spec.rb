require "rails_helper"

RSpec.describe ModelClient do
  let(:url) { "http://model.test" }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:now) { Time.utc(2026, 11, 10, 12) }
  let(:clock) { -> { now } }
  let(:client) { described_class.new(url: url, store: store, clock: clock) }
  let(:rows) { [ { id: "1", line: 24.5, features: { "mean_l5" => 20.0 } } ] }
  let(:ok_body) { { model_version: "v1", predictions: [ { id: "1", projection: 23.1, p_over: 0.41, p_under: 0.59, p_push: 0.0 } ] }.to_json }

  def stub_ok = stub_request(:post, "#{url}/predict").to_return(status: 200, body: ok_body, headers: { "Content-Type" => "application/json" })

  it "is disabled without a URL and never touches the network" do
    off = described_class.new(url: nil, store: store)
    expect(off.enabled?).to be(false)
    expect { off.predict(rows) }.to raise_error(described_class::Unavailable, /not configured/)
    expect(a_request(:any, /./)).not_to have_been_made
  end

  it "posts rows and returns the predictions and model version" do
    stub = stub_ok
    result = client.predict(rows)
    expect(result[:model_version]).to eq("v1")
    expect(result[:predictions].first).to include("p_over" => 0.41)
    expect(stub.with { |req| JSON.parse(req.body)["rows"].first["id"] == "1" }).to have_been_requested
  end

  it "sends big requests in batches" do
    stub_ok
    many = Array.new(450) { |i| { id: i.to_s, line: 1.5, features: {} } }
    client.predict(many)
    expect(a_request(:post, "#{url}/predict")).to have_been_made.times(3)
  end

  it "turns timeouts, connection errors and 5xx into Unavailable" do
    stub_request(:post, "#{url}/predict").to_timeout
    expect { client.predict(rows) }.to raise_error(described_class::Unavailable)
    stub_request(:post, "#{url}/predict").to_return(status: 503)
    expect { client.predict(rows) }.to raise_error(described_class::Unavailable)
    stub_request(:post, "#{url}/predict").to_raise(Faraday::ConnectionFailed)
    expect { client.predict(rows) }.to raise_error(described_class::Unavailable)
  end

  describe "circuit breaker" do
    before { stub_request(:post, "#{url}/predict").to_return(status: 500) }

    it "opens after three failures in a row and then stops calling the service" do
      3.times { expect { client.predict(rows) }.to raise_error(described_class::Unavailable) }
      expect(client.open?).to be(true)
      expect { client.predict(rows) }.to raise_error(described_class::Unavailable, /circuit open/)
      expect(a_request(:post, "#{url}/predict")).to have_been_made.times(3) # the fourth call never left the process
    end

    it "closes again after the pause and recovers" do
      3.times { expect { client.predict(rows) }.to raise_error(described_class::Unavailable) }
      later = described_class.new(url: url, store: store, clock: -> { now + 6.minutes })
      expect(later.open?).to be_falsey
      stub_ok
      expect(later.predict(rows)[:model_version]).to eq("v1")
    end

    it "resets the failure count on success, so scattered failures never trip it" do
      2.times { expect { client.predict(rows) }.to raise_error(described_class::Unavailable) }
      stub_ok
      client.predict(rows)
      stub_request(:post, "#{url}/predict").to_return(status: 500)
      2.times { expect { client.predict(rows) }.to raise_error(described_class::Unavailable) }
      expect(client.open?).to be_falsey
    end
  end
end
