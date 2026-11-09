require "rails_helper"

RSpec.describe "Preferences" do
  it "stores the odds format on the signed-in user" do
    user = create(:user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
    patch preferences_path, params: { odds_format: "decimal" }
    expect(user.reload.odds_format).to eq("decimal")
  end

  it "ignores unknown formats" do
    patch preferences_path, params: { odds_format: "fractional" }
    get "/styleguide"
    expect(response.body).to include("+150")
  end
end
