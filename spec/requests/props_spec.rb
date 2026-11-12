require "rails_helper"

RSpec.describe "Props explorer" do
  seed_fixtures_once

  it "renders the table and cards from precomputed data, with legend and update time" do
    get "/nba/props"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Props explorer", "Legend", "Updated", "Best price")
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
      expect(response.body).to match(/data-filters-target="badge"[^>]*>1</) # the Filters badge counts it
      expect(response.body).to match(/Propositions.*data-chip-count[^>]*>1</m) # and the Propositions button shows how many
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

  describe "the filters toolbar" do
    it "sits under the header with the quick dropdowns, the alt-lines toggle and the count, all in one form" do
      get "/nba/props"
      body = response.body
      expect(body).to include('id="filters_form"', "Filters", "Saved", "Propositions", "Players", "Games", "Over / Under", "Show alt lines")
      expect(body.index("Props explorer")).to be < body.index('id="filters_form"')
      expect(body.index('id="filters_form"')).to be < body.index("Legend") # the results come after it
      expect(body).to match(%r{data-filters-target="count"[^>]*>[\d,]+ props?<})
    end

    it "has a dropdown or toggle for every filter, inside the one form: Only EV+, odds, hit rate and opponent matchup too" do
      get "/nba/props"
      form = response.body[%r{<form[^>]*id="filters_form".*?</form>}m]
      expect(form).to include("Only EV+", "Odds", "Hit rate", "Opponent matchup")
      %w[ev odds_min odds_max min_hit_rate hit_window tier alt side q].each { |name| expect(form).to match(/name="#{name}"/) }
      expect(form).to match(/name="market_types\[\]"/)
      expect(form).to match(/name="game_ids\[\]"/)
    end

    it "keeps only the books filter in the side panel, tied to the same form" do
      get "/nba/props"
      panel = response.body[%r{<aside[^>]*aria-label="Filters".*?</aside>}m]
      expect(panel).to match(/name="book_keys\[\]"[^>]*form="filters_form"|form="filters_form"[^>]*name="book_keys\[\]"/)
      %w[odds_min min_hit_rate tier].each { |name| expect(panel).not_to include(%(name="#{name}")) } # no second copy to fall out of step
    end

    it "marks Only EV+, and shows each prop's edge under its price, when it is on" do
      get "/nba/props", params: { ev: "1" }
      expect(response.body).to match(/data-group="ev" data-active="true"/)
      expect(response.body).to match(/checked="checked"[^>]*name="ev"|name="ev"[^>]*checked="checked"/)
      expect(response.body).to match(/EV \+\d+\.\d%/) # the edge under the price
      get "/nba/props"
      expect(response.body).to match(/data-group="ev" data-active="false"/)
      expect(response.body).not_to include("EV +")
    end

    it "shows no badge or clear button until a filter is set, and both once one is" do
      get "/nba/props"
      expect(response.body).to match(/data-filters-target="badge" hidden/)
      expect(response.body).to match(/Clear all filters.*?hidden|hidden[^>]*Clear all filters/m)
      get "/nba/props", params: { side: "over", alt: "1" }
      expect(response.body).to match(/data-filters-target="badge"[^>]*>2</)
      expect(response.body).not_to match(/data-filters-target="badge" hidden/)
    end

    it "marks the dropdowns that have something chosen" do
      get "/nba/props", params: { side: "under" }
      expect(response.body).to match(/data-group="side" data-active="true"/)
      expect(response.body).to match(/data-group="games" data-active="false"/)
    end

    it "carries the new total in the results frame, for the toolbar to show" do
      get "/nba/props", params: { market_types: [ "player_rebounds" ], side: "under" }
      total = response.body[/data-total="(\d+)"/, 1].to_i
      expect(total).to be_positive
      label = "#{ActiveSupport::NumberHelper.number_to_delimited(total)} #{'prop'.pluralize(total)}"
      expect(response.body).to include(%(data-count-label="#{label}"), %(data-apply-label="Show #{label}"))
      expect(response.body).to match(%r{data-filters-target="count"[^>]*>#{Regexp.escape(label)}<}) # the toolbar agrees with the results
      get "/nba/props"
      expect(response.body[/data-total="(\d+)"/, 1].to_i).to be > total
    end

    it "no longer needs a separate count request: the results frame carries the total" do
      paths = Rails.application.routes.routes.map { |r| r.path.spec.to_s }
      expect(paths).not_to include(a_string_matching(%r{props/count}))
    end
  end

  describe "the books panel" do
    it "offers select all, deselect all and a running count, and will not submit an empty choice" do
      get "/nba/props"
      panel = response.body[%r{<aside[^>]*aria-label="Sportsbooks".*?</aside>}m]
      expect(panel).to include("Select all", "Deselect all", "data-checklist-target=\"count\"", 'data-checklist-minimum-value="1"')
      expect(panel).to match(/data-checklist-target="submit"/)
      expect(panel.scan('data-checklist-target="box"').size).to eq(Bookmaker.count)
    end

    it "still refuses to save no books on the server" do
      patch "/books", params: { keys: [] }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/at least one book/i)
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
