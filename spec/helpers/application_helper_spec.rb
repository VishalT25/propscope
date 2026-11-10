require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#format_price" do
    it "formats American odds with a plus sign" do
      expect(helper.format_price(150, format: "american")).to eq("+150")
      expect(helper.format_price(-110, format: "american")).to eq("-110")
      expect(helper.format_price(100, format: "american")).to eq("+100")
    end

    it "formats decimal odds to two places" do
      expect(helper.format_price(-110, format: "decimal")).to eq("1.91")
      expect(helper.format_price(150, format: "decimal")).to eq("2.50")
      expect(helper.format_price(100, format: "decimal")).to eq("2.00")
    end

    it "shows a dash for missing prices" do
      expect(helper.format_price(nil, format: "american")).to eq("–")
    end
  end

  describe "hit rate styling" do
    it "maps percentages to tones" do
      expect(helper.hit_rate_tone(70, 10)).to eq(:hit)
      expect(helper.hit_rate_tone(30, 10)).to eq(:miss)
      expect(helper.hit_rate_tone(50, 10)).to eq(:push)
    end

    it "keeps the colour for small samples and is neutral only for missing data" do
      expect(helper.hit_rate_tone(100, 3)).to eq(:hit)
      expect(helper.hit_rate_tone(nil)).to eq(:muted)
      expect(helper.percent_label(100, 3)).to eq("100%")
      expect(helper.percent_label(nil, 0)).to eq("n/a")
      expect(helper.percent_label(70.4, 10)).to eq("70%")
    end

    it "flags rates that rest on fewer than the minimum games" do
      expect(helper.small_sample?(2)).to be(true)
      expect(helper.small_sample?(0)).to be(false)
      expect(helper.small_sample?(nil)).to be(false)
      expect(helper.small_sample?(ApplicationHelper::MIN_SAMPLE)).to be(false)
    end

    it "tints green above 50 and red below" do
      expect(helper.hit_rate_cell_style(80, 10)).to include("var(--hit)")
      expect(helper.hit_rate_cell_style(20, 10)).to include("var(--miss)")
    end
  end
end
