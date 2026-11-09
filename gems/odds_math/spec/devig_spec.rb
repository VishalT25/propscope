# frozen_string_literal: true

RSpec.describe OddsMath::Devig do
  def probs(*americans) = americans.map { |a| OddsMath.american_to_implied(a) }

  describe ".multiplicative" do
    it "leaves a fair market unchanged" do
      expect(described_class.multiplicative([ BigDecimal("0.5"), BigDecimal("0.5") ])).to eq([ BigDecimal("0.5") ] * 2)
    end

    it "devigs -110/-110 to 50/50" do
      expect(described_class.multiplicative(probs(-110, -110))).to eq([ BigDecimal("0.5") ] * 2)
    end

    it "devigs -150/+130 proportionally" do
      fair = described_class.multiplicative(probs(-150, 130))
      expect(fair.sum).to be_within(BigDecimal("0.000002")).of(1)
      expect(fair.first).to eq(BigDecimal("0.579832"))
    end

    it "works for 3-way markets" do
      fair = described_class.multiplicative(probs(-120, 250, 300))
      expect(fair.sum).to be_within(BigDecimal("0.000003")).of(1)
    end

    it "returns BigDecimal" do
      expect(described_class.multiplicative(probs(-110, -110)).first).to be_a(BigDecimal)
    end
  end

  describe ".power" do
    it "devigs -110/-110 to 50/50" do
      expect(described_class.power(probs(-110, -110))).to all(be_within(BigDecimal("0.000001")).of(BigDecimal("0.5")))
    end

    it "sums to 1" do
      fair = described_class.power(probs(-300, 240))
      expect(fair.sum).to be_within(BigDecimal("0.000002")).of(1)
    end

    it "gives the longshot less than multiplicative does" do
      ps = probs(-500, 350)
      expect(described_class.power(ps).last).to be < described_class.multiplicative(ps).last
    end

    it "returns a fair market unchanged" do
      expect(described_class.power([ BigDecimal("0.3"), BigDecimal("0.7") ])).to eq([ BigDecimal("0.3"), BigDecimal("0.7") ])
    end
  end

  describe ".overround" do
    it "is ~4.76% for -110/-110" do
      expect(described_class.overround(probs(-110, -110))).to be_within(BigDecimal("0.00001")).of(BigDecimal("0.04762"))
    end
  end

  describe "validation" do
    it "needs 2+ outcomes" do
      expect { described_class.multiplicative([ BigDecimal("0.5") ]) }.to raise_error(OddsMath::InvalidProbability)
    end

    it "rejects out-of-range probabilities" do
      expect { described_class.power([ BigDecimal("1.1"), BigDecimal("0.5") ]) }.to raise_error(OddsMath::InvalidProbability)
    end

    it "rejects non-collections" do
      expect { described_class.multiplicative(nil) }.to raise_error(OddsMath::InvalidProbability)
    end
  end
end
