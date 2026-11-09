# frozen_string_literal: true

RSpec.describe OddsMath::Conversions do
  describe ".american_to_decimal" do
    {
      100 => "2.0", -100 => "2.0", 150 => "2.5", -200 => "1.5",
      -110 => "1.9091", 250 => "3.5", -1000 => "1.1", 10_000 => "101.0"
    }.each do |american, decimal|
      it "#{american} => #{decimal}" do
        expect(OddsMath.american_to_decimal(american)).to eq(BigDecimal(decimal))
      end
    end

    it "returns BigDecimal" do
      expect(OddsMath.american_to_decimal(-110)).to be_a(BigDecimal)
    end

    it "accepts numeric strings" do
      expect(OddsMath.american_to_decimal("+150".delete("+"))).to eq(BigDecimal("2.5"))
    end

    [ 0, 50, -99, 99, 100.5, nil, "abc", 1.5 ].each do |bad|
      it "raises for #{bad.inspect}" do
        expect { OddsMath.american_to_decimal(bad) }.to raise_error(OddsMath::InvalidOdds)
      end
    end
  end

  describe ".decimal_to_american" do
    { "2.0" => 100, "2.5" => 150, "1.5" => -200, "1.9091" => -110, "1.1" => -1000, "3.5" => 250 }.each do |d, a|
      it "#{d} => #{a}" do
        expect(OddsMath.decimal_to_american(BigDecimal(d))).to eq(a)
      end
    end

    it "rounds trip for common prices" do
      [ -110, -105, 120, 175, -250, 400 ].each do |a|
        expect(OddsMath.decimal_to_american(OddsMath.american_to_decimal(a))).to eq(a)
      end
    end

    [ "1", "0.5", "-2", 1, 0 ].each do |bad|
      it "raises for #{bad.inspect}" do
        expect { OddsMath.decimal_to_american(bad) }.to raise_error(OddsMath::InvalidOdds)
      end
    end

    it "rejects Float" do
      expect { OddsMath.decimal_to_american(2.5) }.to raise_error(OddsMath::InvalidOdds, /Float/)
    end
  end

  describe ".american_to_implied" do
    it "even money is 50%" do
      expect(OddsMath.american_to_implied(100)).to eq(BigDecimal("0.5"))
      expect(OddsMath.american_to_implied(-100)).to eq(BigDecimal("0.5"))
    end

    it "-110 is ~52.38%" do
      expect(OddsMath.american_to_implied(-110)).to eq(BigDecimal("0.523810"))
    end

    it "heavy favourite -10000 is ~99.01%" do
      expect(OddsMath.american_to_implied(-10_000)).to eq(BigDecimal("0.990099"))
    end

    it "longshot +10000 is ~0.99%" do
      expect(OddsMath.american_to_implied(10_000)).to eq(BigDecimal("0.009901"))
    end
  end

  describe ".decimal_to_implied" do
    it "2.0 is 50%" do
      expect(OddsMath.decimal_to_implied(BigDecimal("2.0"))).to eq(BigDecimal("0.5"))
    end

    it "raises at or below 1" do
      expect { OddsMath.decimal_to_implied(BigDecimal("1.0")) }.to raise_error(OddsMath::InvalidOdds)
    end
  end

  describe ".implied_to_american" do
    it "0.5 => 100" do
      expect(OddsMath.implied_to_american(BigDecimal("0.5"))).to eq(100)
    end

    it "0.6 => -150" do
      expect(OddsMath.implied_to_american(BigDecimal("0.6"))).to eq(-150)
    end

    it "0.25 => 300" do
      expect(OddsMath.implied_to_american(BigDecimal("0.25"))).to eq(300)
    end

    [ "0", "1", "-0.1", "1.2", 0, 1 ].each do |bad|
      it "raises for #{bad.inspect}" do
        expect { OddsMath.implied_to_american(bad) }.to raise_error(OddsMath::InvalidProbability)
      end
    end
  end

  describe ".implied_to_decimal" do
    it "0.4 => 2.5" do
      expect(OddsMath.implied_to_decimal(BigDecimal("0.4"))).to eq(BigDecimal("2.5"))
    end
  end
end
