require "rails_helper"

# Drives the real page. rack_test covers the server-rendered flow (apply, sort, paginate, reset);
# the JS specs (headless Chrome) cover the toolbar: dropdowns, live apply, badges, and the books panel.
RSpec.describe "Filtering props", type: :system do
  seed_fixtures_once

  # The count in the toolbar. Waits for it, so it is never read from a page that has not loaded.
  def total
    number = nil
    page.document.synchronize do
      number = find("[data-filters-target=count]", match: :first, visible: :all).text[/[\d,]+/]
      raise Capybara::ElementNotFound, "the prop count has no number yet" unless number
    end
    number
  end

  context "without JavaScript" do
    before { driven_by(:rack_test) }

    it "filters through the form, keeps the filters in the URL, sorts and resets" do
      visit "/nba/props"
      before = total

      check "Points", visible: :all
      choose "Over", visible: :all
      click_button "Show", match: :first, visible: :all
      expect(page).to have_current_path(/market_types/)
      expect(page).to have_current_path(/side=over/)
      expect(total).not_to eq(before)
      expect(page).to have_content("Over").and have_no_content("Under 1")

      first("th a", text: "L5").click
      expect(page).to have_current_path(/sort=l5/)
      expect(page).to have_content("L5")

      click_link "Reset", match: :first, visible: :all
      expect(total).to eq(before)
    end

    it "takes the side panel's fields into the same filter" do
      visit "/nba/props"
      fill_in "min_hit_rate", with: "90", visible: :all
      click_button "Show", match: :first, visible: :all
      expect(page).to have_current_path(/min_hit_rate=90/)
    end

    it "lets a guest choose books and see prices change" do
      visit "/nba/props"
      expect(page).to have_content("+3") # 5 books enabled: two badges plus a count
      page.driver.submit :patch, "/books", { keys: [ "caesars" ] }
      visit "/nba/props"
      expect(page).to have_content("CZR")
      expect(page).to have_no_content("+3")
    end
  end

  context "with JavaScript", :js do
    before do
      driven_by(:selenium, using: :headless_chrome, screen_size: [ 1280, 900 ])
    rescue StandardError => e
      skip "headless Chrome unavailable: #{e.message}"
    end

    it "applies a dropdown choice at once: the list, the count, the URL and the badges all follow" do
      visit "/nba/props"
      before = total
      expect(page).to have_css("[data-filters-target=badge][hidden]", visible: :all)

      click_button "Propositions"
      check "3-Pointers Made"
      expect(page).to have_current_path(/market_types/, wait: 5)
      expect(page).to have_css("[data-filters-target=count]", text: /props?\z/)
      expect(page).to have_no_css("[data-filters-target=count]", text: before, wait: 5)
      expect(page).to have_css("[data-filters-target=badge]", text: "1")
      expect(page).to have_css("button[data-group=propositions][data-active=true] [data-chip-count]", text: "1")
      expect(page).to have_css("a[aria-label='Clear all filters']")
      expect(page).to have_no_content("Rebounds</td>") # only the one stat is listed
    end

    it "clears everything with the cross next to Filters" do
      visit "/nba/props"
      before = total
      click_button "Over / Under"
      choose "Over", allow_label_click: true
      expect(page).to have_current_path(/side=over/, wait: 5)
      expect(page).to have_css("button[data-group=side][data-active=true]")

      find("a[aria-label='Clear all filters']").click
      expect(page).to have_no_current_path(/side=over/, wait: 5)
      expect(total).to eq(before)
      expect(page).to have_css("[data-filters-target=badge][hidden]", visible: :all)
    end

    it "turns alt lines on and off from the toggle" do
      visit "/nba/props"
      find("label", text: "Show alt lines").click
      expect(page).to have_current_path(/alt=1/, wait: 5)
      expect(page).to have_css("[data-filters-target=badge]", text: "1")
    end

    it "keeps the dropdown open while you tick several things, and closes it on Escape" do
      visit "/nba/props"
      click_button "Propositions"
      check "Points"
      expect(page).to have_current_path(/player_points/, wait: 5)
      expect(page).to have_checked_field("Points")
      check "Assists"
      expect(page).to have_css("button[data-group=propositions] [data-chip-count]", text: "2", wait: 5)
      page.send_keys(:escape)
      expect(page).to have_no_field("Assists", visible: :visible)
    end

    it "searches players as you type" do
      visit "/nba/props"
      click_button "Players"
      fill_in "Player name", with: "zzzznobody"
      expect(page).to have_content("No props match", wait: 5)
      expect(page).to have_current_path(/q=zzzznobody/)
    end

    it "applies the side panel's filters live as well, and its button closes the panel" do
      visit "/nba/props"
      click_button "Filters"
      fill_in "min_hit_rate", with: "100"
      expect(page).to have_current_path(/min_hit_rate=100/, wait: 5)
      label = find("#apply_label").text
      expect(label).to match(/Show [\d,]+ props?/)
      click_button label
      expect(page).to have_no_css("aside[aria-label=Filters]", visible: :visible)
    end

    it "saves the filters as they are on screen now, including the dropdowns, not as the page was loaded" do
      allow(Rails.configuration.x).to receive(:single_user).and_return(true)
      visit "/nba/props"
      click_button "Propositions"
      check "Points"
      expect(page).to have_current_path(/player_points/, wait: 5)
      page.send_keys(:escape)
      click_button "Over / Under"
      choose "Under", allow_label_click: true
      expect(page).to have_current_path(/side=under/, wait: 5)
      page.send_keys(:escape)

      click_button "Filters"
      fill_in "name", with: "Points unders"
      click_button "Save", exact: true
      expect(page).to have_content("Saved “Points unders”", wait: 5)

      saved = SavedFilter.find_by!(name: "Points unders")
      expect(saved.params).to include("market_types" => [ "player_points" ], "side" => "under")
    end

    describe "the books panel" do
      def open_books = find("button[title='Which books count toward best price']").click

      it "selects all, deselects all, counts them, and will not let you finish with none" do
        visit "/nba/props"
        open_books
        within("aside[aria-label=Sportsbooks]") do
          count = Bookmaker.count
          expect(page).to have_content("#{count} of #{count} books on")

          click_button "Deselect all"
          expect(page).to have_content("0 of #{count} books on")
          expect(page).to have_no_checked_field(visible: :all)
          expect(page).to have_button("Done", disabled: true)

          click_button "Select all"
          expect(page).to have_content("#{count} of #{count} books on")
          expect(page).to have_button("Done", disabled: false)

          click_button "Deselect all"
          find("label", text: "Caesars").click
          expect(page).to have_content("1 of #{count} books on")
          expect(page).to have_button("Done", disabled: false)
        end
      end

      it "saves a smaller choice, and select all brings every book back" do
        visit "/nba/props"
        open_books
        within("aside[aria-label=Sportsbooks]") do
          click_button "Deselect all"
          find("label", text: "Caesars").click
          click_button "Done"
        end
        expect(page).to have_css("table", text: "CZR")
        expect(page).to have_no_css("tbody", text: /\b(MGM|DK|FD|ESPN)\b/)

        open_books
        within("aside[aria-label=Sportsbooks]") do
          click_button "Select all"
          click_button "Done"
        end
        expect(page).to have_css("tbody", text: /\b(MGM|DK|FD|ESPN)\b/)
      end
    end
  end
end
