# frozen_string_literal: true

RSpec.describe OddsMath::Arbitrage do
  def d(*values) = values.map { |v| BigDecimal(v) }

  it "detects an arbitrage when the best prices imply under 100%" do
    expect(described_class.arbitrage?(d("2.10", "2.05"))).to be(true)
    expect(described_class.arbitrage?(d("1.91", "1.91"))).to be(false)
    expect(described_class.arbitrage?(d("2.0", "2.0"))).to be(false) # exactly 100%: no edge
  end

  it "computes the guaranteed profit as a fraction of the stake" do
    expect(described_class.profit(d("2.10", "2.05")).round(4)).to eq(BigDecimal("0.0373"))
    expect(described_class.profit(d("1.91", "1.91"))).to be < 0
  end

  it "splits a stake so both outcomes pay out within a cent at typical odds" do
    [ [ "100", %w[2.10 2.05] ], [ "250.55", %w[2.37 1.97] ], [ "1000", %w[1.95 2.15] ], [ "75", %w[2.20 1.95] ] ].each do |total, odds|
      split = described_class.split(total: total, decimal_odds: d(*odds))
      expect(split.sum { |s| s[:stake] }).to eq(BigDecimal(total))
      payouts = split.map { |s| s[:payout] }
      expect(payouts.max - payouts.min).to be <= BigDecimal("0.01")
      expect(split).to all(satisfy { |s| s[:stake] == s[:stake].round(2) })
    end
  end

  it "stays as close as whole-cent stakes allow at long odds (a cent of stake moves the payout by the odds in cents)" do
    split = described_class.split(total: "37.31", decimal_odds: d("3.40", "1.45"))
    expect(split.sum { |s| s[:stake] }).to eq(BigDecimal("37.31"))
    expect(split.map { |s| s[:payout] }.minmax.reduce(:-).abs).to be <= BigDecimal("0.03")
  end

  it "makes a profit on every outcome when it is a real arbitrage" do
    split = described_class.split(total: "100", decimal_odds: d("2.10", "2.05"))
    expect(split.map { |s| s[:payout] }).to all(be > 100)
  end

  it "handles three outcomes" do
    split = described_class.split(total: "90", decimal_odds: d("3.2", "3.5", "3.6"))
    expect(split.sum { |s| s[:stake] }).to eq(90)
    expect(split.map { |s| s[:payout] }.minmax.reduce(:-).abs).to be <= BigDecimal("0.02")
  end

  it "rejects bad input" do
    expect { described_class.split(total: "0", decimal_odds: d("2", "2")) }.to raise_error(OddsMath::InvalidOdds)
    expect { described_class.total_implied(d("2")) }.to raise_error(OddsMath::InvalidOdds)
    expect { described_class.total_implied([ BigDecimal("1"), BigDecimal("2") ]) }.to raise_error(OddsMath::InvalidOdds)
    expect { described_class.total_implied([ 2.0, 2.0 ]) }.to raise_error(OddsMath::InvalidOdds, /Float/)
  end
end
