require "rails_helper"

RSpec.describe Providers::HttpTransport do
  let(:transport) do
    described_class.new(provider: "test_provider", base_url: "https://api.example.test/v1/", min_interval: 0,
                        auth: -> { { "X-Api-Key" => "secret" } })
  end

  before { allow_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep) }

  it "sends the auth header and parses JSON" do
    stub = stub_request(:get, "https://api.example.test/v1/events").with(headers: { "X-Api-Key" => "secret" }, query: { "a" => "1" })
                                                                    .to_return(status: 200, body: '{"ok":true}', headers: { "Content-Type" => "application/json" })
    expect(transport.get("/events", "a" => "1")).to eq({ "ok" => true })
    expect(stub).to have_been_requested
  end

  it "retries 429 and 5xx with backoff, then succeeds" do
    stub_request(:get, "https://api.example.test/v1/x").to_return({ status: 429 }, { status: 503 },
                                                                  { status: 200, body: "{}", headers: { "Content-Type" => "application/json" } })
    expect(transport.get("/x")).to eq({})
    expect(a_request(:get, "https://api.example.test/v1/x")).to have_been_made.times(3)
  end

  it "raises after exhausting retries" do
    stub_request(:get, "https://api.example.test/v1/y").to_return(status: 500)
    expect { transport.get("/y") }.to raise_error(Faraday::ServerError)
  end

  it "does not retry client errors" do
    stub_request(:get, "https://api.example.test/v1/z").to_return(status: 401)
    expect { transport.get("/z") }.to raise_error(Faraday::UnauthorizedError)
    expect(a_request(:get, "https://api.example.test/v1/z")).to have_been_made.once
  end

  it "is metered and throttles calls to the provider's minimum interval" do
    throttled = described_class.new(provider: "slow_provider", base_url: "https://api.example.test/v1/", min_interval: 5, auth: -> { {} })
    stub_request(:get, "https://api.example.test/v1/t").to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })
    expect(throttled.metered?).to be(true)
    allow(throttled).to receive(:sleep)
    throttled.get("/t")
    throttled.get("/t")
    expect(throttled).to have_received(:sleep).with(be_within(0.5).of(5)).once
  end
end
