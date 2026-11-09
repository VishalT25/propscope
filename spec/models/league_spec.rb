require "rails_helper"

RSpec.describe League do
  it "finds case-insensitively and defaults to NBA" do
    expect(described_class.find("NBA").name).to eq("NBA")
    expect(described_class.find("bogus")).to be_nil
    expect(described_class.default.key).to eq("nba")
  end

  it "only enables NBA for the MVP" do
    expect(described_class::ALL.select(&:enabled?).map(&:key)).to eq(%w[nba])
  end
end
