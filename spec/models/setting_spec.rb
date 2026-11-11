require "rails_helper"

RSpec.describe Setting do
  it "stores values encrypted: the column never holds the plain text" do
    described_class.set("api_key.demo", "super-secret-key-1234")
    raw = described_class.connection.select_value("SELECT value FROM settings WHERE key = 'api_key.demo'")
    expect(raw).not_to include("super-secret-key-1234")
    expect(described_class.get("api_key.demo")).to eq("super-secret-key-1234")
  end

  it "replaces a value, and deletes one when set to blank" do
    described_class.set("mode", "a")
    described_class.set("mode", "b")
    expect([ described_class.where(key: "mode").count, described_class.get("mode") ]).to eq([ 1, "b" ])
    described_class.set("mode", "")
    expect(described_class.get("mode", "fallback")).to eq("fallback")
  end

  it "reads the default for a missing key, and for a value that can no longer be decrypted (SECRET_KEY_BASE changed)" do
    expect(described_class.get("nothing", "dflt")).to eq("dflt")
    described_class.set("broken", "x")
    described_class.connection.execute("UPDATE settings SET value = 'not valid ciphertext' WHERE key = 'broken'")
    expect(described_class.get("broken", "dflt")).to eq("dflt")
  end
end

RSpec.describe ApiKeys do
  def with_env(vars) = stub_const("ENV", ENV.to_h.merge(vars))

  it "has no key on a fresh install, and says what to do" do
    expect([ described_class.get("balldontlie"), described_class.source("balldontlie"), described_class.hint("balldontlie") ]).to eq([ nil, nil, nil ])
    expect { described_class.fetch("balldontlie") }.to raise_error(ApiKeys::Missing, /BallDontLie.*Settings/)
  end

  it "uses the key saved in the app, and only ever hints at it" do
    described_class.set("balldontlie", "  abcd-1234-wxyz  ")
    expect([ described_class.fetch("balldontlie"), described_class.source("balldontlie"), described_class.hint("balldontlie") ]).to eq([ "abcd-1234-wxyz", :app, "••••wxyz" ])
  end

  it "lets the environment win over a saved key" do
    described_class.set("sports_game_odds", "from-the-app")
    with_env("SPORTSGAMEODDS_API_KEY" => "from-the-env")
    expect([ described_class.fetch("sports_game_odds"), described_class.source("sports_game_odds") ]).to eq([ "from-the-env", :environment ])
  end

  it "forgets a key, and rejects an unknown provider" do
    described_class.set("balldontlie", "k")
    described_class.clear("balldontlie")
    expect(described_class.present?("balldontlie")).to be(false)
    expect { described_class.get("nope") }.to raise_error(KeyError)
  end

  it "never lets the keys reach the logs" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("api_key" => "secret", "keys" => { "balldontlie" => "secret" }, "name" => "ok")
    expect(filtered).to eq("api_key" => "[FILTERED]", "keys" => "[FILTERED]", "name" => "ok")
  end
end

RSpec.describe LiveData do
  it "is off by default" do
    expect(described_class.enabled?).to be(false)
  end

  it "turns on from the environment or from setup" do
    stub_const("ENV", ENV.to_h.merge("LIVE_DATA" => "true"))
    expect(described_class.enabled?).to be(true)
  end

  it "turns on when setup chose live data, and back off for sample data" do
    Setting.set("data_mode", "live")
    expect(described_class.enabled?).to be(true)
    Setting.set("data_mode", "sample")
    expect(described_class.enabled?).to be(false)
  end
end

RSpec.describe Providers::Registry do
  it "paces BallDontLie by plan: the free plan allows 5 requests a minute, the paid plan 60" do
    expect(described_class.min_interval("balldontlie")).to eq(1.1)
    Setting.set("balldontlie_plan", "free")
    expect(described_class.min_interval("balldontlie")).to eq(12.5)
    expect(described_class.min_interval("sports_game_odds")).to eq(6.5)
  end

  it "builds a live adapter that reads its key from the app (and complains clearly without one)" do
    Setting.set("data_mode", "live")
    adapter = described_class.for(:stats)
    expect(adapter.provider_key).to eq("balldontlie")
    auth = adapter.transport.instance_variable_get(:@auth)
    expect { auth.call }.to raise_error(ApiKeys::Missing)
    ApiKeys.set("balldontlie", "k-123")
    expect(auth.call).to eq({ "Authorization" => "k-123" })
  end
end
