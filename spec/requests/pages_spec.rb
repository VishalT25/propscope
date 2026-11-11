require "rails_helper"

RSpec.describe "Public pages" do
  it "serves Home at the root, for guests too" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your slips")
  end

  %w[props games insights].each do |page|
    it "renders #{page} for guests" do
      get "/nba/#{page}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Propscope")
    end
  end

  it "404s for unknown leagues" do
    get "/curling/props"
    expect(response).to have_http_status(:not_found)
  end

  it "renders the styleguide" do
    get "/styleguide"
    expect(response.body).to include("Hit-rate bar")
  end

  it "shows American prices by default and decimal after switching" do
    get "/styleguide"
    expect(response.body).to include("-110").and include("+150")

    patch "/preferences", params: { odds_format: "decimal" }
    follow_redirect!
    get "/styleguide"
    expect(response.body).to include("1.91").and include("2.50")
  end
end
