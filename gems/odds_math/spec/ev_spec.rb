# frozen_string_literal: true

RSpec.describe OddsMath::Ev do
  let(:p) { BigDecimal("0.55") }

  describe ".expected_value" do
    it "is positive when price beats fair" do
      expect(described_class.expected_value(fair_probability: p, decimal_odds: BigDecimal("2.0"))).to eq(BigDecimal("0.1"))
    end

    it "is zero at the fair price" do
      expect(described_class.expected_value(fair_probability: BigDecimal("0.5"), decimal_odds: BigDecimal("2.0"))).to eq(0)
    end

    it "is negative when price is worse than fair" do
      expect(described_class.expected_value(fair_probability: BigDecimal("0.4"), decimal_odds: BigDecimal("2.0"))).to be < 0
    end

    it "rejects Float odds" do
      expect { described_class.expected_value(fair_probability: p, decimal_odds: 2.0) }.to raise_error(OddsMath::InvalidOdds)
    end

    it "rejects decimal odds <= 1" do
      expect { described_class.expected_value(fair_probability: p, decimal_odds: BigDecimal("1")) }.to raise_error(OddsMath::InvalidOdds)
    end
  end

  describe ".kelly" do
    it "computes full Kelly (edge / (odds - 1))" do
      expect(described_class.kelly(fair_probability: p, decimal_odds: BigDecimal("2.0"))).to eq(BigDecimal("0.1"))
    end

    it "scales by multiplier" do
      expect(described_class.kelly(fair_probability: p, decimal_odds: BigDecimal("2.0"), multiplier: BigDecimal("0.25"))).to eq(BigDecimal("0.025"))
    end

    it "is zero with no edge" do
      expect(described_class.kelly(fair_probability: BigDecimal("0.4"), decimal_odds: BigDecimal("2.0"))).to eq(0)
    end

    it "rejects a multiplier outside (0, 1]" do
      expect { described_class.kelly(fair_probability: p, decimal_odds: BigDecimal("2.0"), multiplier: BigDecimal("2")) }.to raise_error(OddsMath::Error)
    end
  end
end
