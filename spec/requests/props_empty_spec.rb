require "rails_helper"

# What the Props page says when there is nothing to list. No fixtures are loaded here on purpose.
RSpec.describe "Props explorer with nothing to show" do
  before { allow(Rails.configuration.x).to receive(:single_user).and_return(true) }

  it "explains sample data: it is re-dated by itself, and offers to do it now" do
    Setting.set("data_mode", "sample")
    get "/nba/props"
    expect(response.body).to include("No props to show yet", "re-dated automatically", "Refresh sample data")
    expect(response.body).not_to include("db:seed") # that advice is gone
  end

  context "with live data" do
    before do
      Setting.set("data_mode", "live")
      BackfillRun.create!(state: "done") # setup is complete
    end

    it "says what is normal (lines go up on game day), when the next game is, how odds arrive, and offers to fetch them" do
      create(:game, starts_at: 30.hours.from_now)
      get "/nba/props"
      body = response.body
      expect(body).to include("No props to show yet", "usually post player props on the day of the game", "Next game:", "How odds arrive", "background worker", "Refresh odds now", "allowance")
      expect(body).to include(refresh_odds_setup_path)
      expect(body).not_to include("db:seed")
    end

    it "puts the action before the explanation, and keeps the explanation out of the way until asked for" do
      create(:game, starts_at: 30.hours.from_now)
      get "/nba/props"
      body = response.body
      expect(body.index("Next game:")).to be < body.index("Refresh odds now")
      expect(body.index("Refresh odds now")).to be < body.index("How odds arrive")
      expect(body).to match(%r{<details[^>]*>\s*<summary[^>]*>How odds arrive})
    end

    it "does not promise a next game when there is none" do
      get "/nba/props"
      expect(response.body).not_to include("Next game:")
    end

    it "does not offer the button to someone who cannot use it" do
      allow(Rails.configuration.x).to receive(:single_user).and_return(false)
      post session_path, params: { email_address: create(:user).email_address, password: "password123" }
      get "/nba/props"
      expect(response.body).to include("No props to show yet")
      expect(response.body).not_to include("Refresh odds now")
    end

    it "still says 'No props match' when filters are the reason" do
      get "/nba/props", params: { q: "zzzznobody" }
      expect(response.body).to include("No props match", "reset them all")
      expect(response.body).not_to include("No props to show yet")
    end
  end
end
