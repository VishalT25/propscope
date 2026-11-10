require "rails_helper"

RSpec.describe "Props explorer" do
  seed_fixtures_once

  it "renders the table and cards from precomputed data, with legend and update time" do
    get "/nba/props"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Props explorer", "Legend", "updated", "Best price")
    expect(response.body).to match(/\d+ props/)
  end

  it "never calls an external API while rendering (golden rule)" do
    allow(Providers::Registry).to receive(:for).and_raise("page requests must not touch providers")
    get "/nba/props"
    expect(response).to have_http_status(:ok)
  end

  it "shows prices in the viewer's odds format" do
    get "/nba/props"
    expect(response.body).to match(/[+-]\d{3}/)
    patch "/preferences", params: { odds_format: "decimal" }
    get "/nba/props"
    expect(response.body).to match(/\b\d\.\d{2}\b/)
  end

  describe "filtering" do
    it "narrows by market type and reflects the filters in the count and badge" do
      get "/nba/props", params: { market_types: [ "player_assists" ] }
      expect(response.body).to include("Assists")
      expect(response.body).not_to include("3-Pointers Made</td>")
      expect(response.body).to include('title="Current filters"')
    end

    it "shows the empty state when nothing matches" do
      get "/nba/props", params: { q: "zzzznobody" }
      expect(response.body).to include("No props match")
    end

    it "ignores garbage params" do
      get "/nba/props", params: { sort: "'; drop table", dir: "sideways", page: "abc", odds_min: "x" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "sorting and pagination" do
    it "marks the sorted column and flips direction on the header link" do
      get "/nba/props", params: { sort: "l5", dir: "asc" }
      expect(response.body).to include("L5 ↑")
      expect(response.body).to match(/dir=desc&amp;sort=l5|sort=l5&amp;dir=desc/)
    end

    it "paginates 50 per page" do
      get "/nba/props"
      expect(response.body.scan("<tr class=\"fade-row hover:bg-surface-2/60\"").size).to eq(50)
      expect(response.body).to include("Page 1 of")
      get "/nba/props", params: { page: 2 }
      expect(response.body).to include("Page 2 of")
    end
  end

  describe "live result count (Turbo Stream)" do
    it "returns the new button label for the filters" do
      get "/nba/props/count", params: { market_types: [ "player_points" ], side: "over" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="apply_label"')
      expect(response.body).to match(/Show \d+ props/)
    end

    it "matches the number of results the list shows" do
      params = { market_types: [ "player_rebounds" ], side: "under" }
      get "/nba/props/count", params: params, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      count = response.body[/Show ([\d,]+) props?/, 1].delete(",").to_i
      get "/nba/props", params: params
      expect(response.body).to include("<span class=\"font-semibold text-fg\">#{ActiveSupport::NumberHelper.number_to_delimited(count)}</span>")
    end
  end

  describe "book selector" do
    let(:keys) { Bookmaker.order(:key).pluck(:key) }

    it "stores the choice in a cookie for guests and re-prices everything" do
      get "/nba/props"
      expect(response.body).to include("MGM")
      patch "/books", params: { keys: [ "caesars" ] }
      expect(response).to redirect_to(root_path)
      get "/nba/props"
      table = response.body[/<tbody.*<\/tbody>/m]
      expect(table).to include("CZR")
      expect(table).not_to match(/>(MGM|DK|FD|ESPN)</)
    end

    it "persists to the user when signed in" do
      user = create(:user)
      post session_path, params: { email_address: user.email_address, password: "password123" }
      patch "/books", params: { keys: %w[fanduel draftkings] }
      expect(user.reload.enabled_bookmaker_keys).to contain_exactly("fanduel", "draftkings")
    end

    it "stores nil (all books) when everything is selected" do
      user = create(:user)
      post session_path, params: { email_address: user.email_address, password: "password123" }
      patch "/books", params: { keys: keys }
      expect(user.reload.enabled_bookmaker_keys).to be_nil
    end

    it "refuses to disable every book" do
      patch "/books", params: { keys: [] }
      expect(flash[:alert]).to eq("Keep at least one book enabled.")
      expect(cookies[:enabled_books]).to be_blank
    end

    it "ignores unknown books and corrupt cookies" do
      patch "/books", params: { keys: %w[not_a_book fanduel] }
      cookies[:enabled_books] = "{not json"
      get "/nba/props"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "saved filters" do
    let(:user) { create(:user) }

    it "requires sign-in to save" do
      post "/saved_filters", params: { name: "x", side: "over" }
      expect(response).to redirect_to(new_session_path)
    end

    context "signed in" do
      before { post session_path, params: { email_address: user.email_address, password: "password123" } }

      it "saves the applied filters, lists them under Saved, and can delete them" do
        post "/saved_filters", params: { name: "Overs on assists", side: "over", market_types: [ "player_assists" ], min_hit_rate: "70" }
        saved = user.saved_filters.last
        expect(saved.params).to include("side" => "over", "market_types" => [ "player_assists" ], "min_hit_rate" => 70)
        expect(response).to redirect_to(league_props_path("nba", saved.params.symbolize_keys))

        get "/nba/props"
        expect(response.body).to include("Overs on assists")
        delete "/saved_filters/#{saved.id}"
        expect(user.saved_filters.count).to eq(0)
      end

      it "rejects a blank name" do
        post "/saved_filters", params: { name: " ", side: "over" }
        expect(user.saved_filters.count).to eq(0)
      end

      it "cannot delete someone else's filter" do
        other = SavedFilter.create!(user: create(:user), name: "theirs", scope: "props", params: {})
        delete "/saved_filters/#{other.id}"
        expect(response).to have_http_status(:not_found)
        expect(SavedFilter.exists?(other.id)).to be(true)
      end
    end
  end
end
