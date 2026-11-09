require "rails_helper"

RSpec.describe User do
  it "defaults to american odds and non-admin" do
    user = build(:user)
    expect(user.odds_format).to eq("american")
    expect(user).not_to be_admin
  end

  it "normalizes email" do
    expect(create(:user, email_address: "  Foo@Example.COM ").email_address).to eq("foo@example.com")
  end

  it "rejects short passwords, bad emails and unknown odds formats" do
    expect(build(:user, password: "short")).not_to be_valid
    expect(build(:user, email_address: "nope")).not_to be_valid
    expect(build(:user, odds_format: "fractional")).not_to be_valid
  end

  it "enforces unique emails" do
    create(:user, email_address: "a@example.com")
    expect(build(:user, email_address: "A@example.com")).not_to be_valid
  end
end
