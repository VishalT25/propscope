require "rails_helper"

RSpec.describe NameNormalizer do
  {
    "Dušan Marković" => "dusan markovic",
    "Luka Dončić" => "luka doncic",
    "Jaylen Brooks Jr." => "jaylen brooks",
    "Nikolas Petrović III" => "nikolas petrovic",
    "Tyrese Gilmore-Adeyemi" => "tyrese gilmore adeyemi",
    "Tyrese Gilmore Adeyemi" => "tyrese gilmore adeyemi",
    "D'Angelo Russell" => "dangelo russell",
    "Mike Stanhope" => "michael stanhope",
    "  Michael   Stanhope " => "michael stanhope",
    "Nic Claxton" => "nicolas claxton",
    "Gary Payton II" => "gary payton"
  }.each do |input, expected|
    it "#{input.inspect} => #{expected.inspect}" do
      expect(described_class.call(input)).to eq(expected)
    end
  end

  it "does not strip a lone suffix-like name" do
    expect(described_class.call("V")).to eq("v")
  end

  it "handles nil" do
    expect(described_class.call(nil)).to eq("")
  end

  it "makes accented, suffixed and nicknamed variants equal" do
    expect(described_class.call("Mike Stanhope Jr.")).to eq(described_class.call("Michael Stanhope"))
  end
end
