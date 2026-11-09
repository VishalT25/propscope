require "rails_helper"

# Drives the real page. rack_test covers the server-rendered flow (apply, sort, paginate, reset);
# the JS spec (headless Chrome) covers the drawer and the live result count.
RSpec.describe "Filtering props", type: :system do
  seed_fixtures_once

  context "without JavaScript" do
    before { driven_by(:rack_test) }

    it "filters through the form, keeps the filters in the URL, sorts and resets" do
      visit "/nba/props"
      total = page.text[/(\d[\d,]*) props/, 1]

      within("#filters_form", visible: :all) do
        check "Points", visible: :all
        choose "Over", visible: :all
        click_button "Show", match: :first, visible: :all
      end
      expect(page).to have_current_path(/market_types/)
      expect(page).to have_current_path(/side=over/)
      expect(page.text[/(\d[\d,]*) props/, 1]).not_to eq(total)
      expect(page).to have_content("Over").and have_no_content("Under 1")

      first("th a", text: "L5").click
      expect(page).to have_current_path(/sort=l5/)
      expect(page).to have_content("L5")

      click_link "Reset", match: :first
      expect(page.text[/(\d[\d,]*) props/, 1]).to eq(total)
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

    it "updates the Show N button live while filters change, then applies them" do
      visit "/nba/props"
      click_button "Filters"
      initial = find("#apply_label").text
      check "3-Pointers Made"
      expect(page).to have_no_css("#apply_label", text: initial, wait: 3)
      live = find("#apply_label").text
      click_button live
      expect(page).to have_current_path(/market_types/)
      expect(page).to have_content(live.sub("Show ", ""))
    end
  end
end
