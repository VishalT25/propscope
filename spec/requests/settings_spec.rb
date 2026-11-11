require "rails_helper"

RSpec.describe "Settings and About" do
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") }
  let(:team) { create(:team, name: "Boston Testers", abbreviation: "BOS") }

  def file(bytes, name: "logo.png", type: "image/png")
    path = Rails.root.join("tmp", "upload-#{SecureRandom.hex(4)}-#{name}")
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path, type, original_filename: name)
  end

  before { allow(Rails.configuration.x).to receive(:single_user).and_return(true) }

  after do # the test disk service and the upload helper both leave real files behind
    FileUtils.rm_rf(Dir[File.join(ActiveStorage::Blob.service.root, "*")]) # not the tracked .keep
    FileUtils.rm_f(Dir[Rails.root.join("tmp", "upload-*")])
  end

  describe "the page" do
    it "shows the About section: version, git details, runtime and the credit" do
      get "/settings"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("About", "v#{BuildInfo::VERSION}", "Made by", "Vishal", "Ruby #{RUBY_VERSION}", "Sample data (fixtures)")
      expect(response.body).to match(/Commit/)
    end

    it "lists teams for logos and finds players by name, accents and case aside" do
      create(:team, name: "Atlanta Testers", abbreviation: "ATL")
      create(:player, first_name: "Dušan", last_name: "Marković")
      get "/settings", params: { q: "dusan MARKOVIC" }
      expect(response.body).to include("Atlanta Testers", "Dušan Marković")
      get "/settings", params: { q: "zzzz" }
      expect(response.body).to include("No player matches")
    end

    it "lists players who already have a photo when nothing is searched" do
      create(:player, first_name: "Has", last_name: "Photo", photo_url: "https://example.test/p.png")
      create(:player, first_name: "No", last_name: "Photo")
      get "/settings"
      expect(response.body).to include("Has Photo")
      expect(response.body).not_to include("No Photo")
    end

    it "is linked from the account menu and the footer" do
      get "/nba/props"
      expect(response.body).to include("Settings and about", "Made by Vishal")
    end
  end

  describe "uploading" do
    it "sets a team logo, shows it on the page and everywhere the badge is used" do
      patch "/settings/logos/#{team.id}", params: { image: file(png) }
      expect(response).to redirect_to(settings_path(anchor: nil))
      expect(flash[:notice]).to eq("Boston Testers logo updated.")
      expect(team.reload.logo).to be_attached

      get "/settings"
      expect(response.body).to include(team.logo_url)
      expect(response.body).to include("Remove")
    end

    it "sets a player photo and keeps the search on the way back" do
      player = create(:player, first_name: "Photo", last_name: "Taker")
      patch "/settings/photos/#{player.id}", params: { image: file(png), q: "taker", section: "photos" }
      expect(response).to redirect_to(settings_path(q: "taker", anchor: "photos"))
      expect(player.reload.photo).to be_attached
    end

    it "explains a refused file and stores nothing" do
      patch "/settings/logos/#{team.id}", params: { image: file("<svg><script>alert(1)</script></svg>", name: "logo.svg", type: "image/svg+xml") }
      expect(flash[:alert]).to match(/not a PNG, JPEG, WebP or GIF/)
      expect(team.reload.logo).not_to be_attached
      patch "/settings/logos/#{team.id}"
      expect(flash[:alert]).to match(/Choose an image/)
    end

    it "removes a logo again" do
      patch "/settings/logos/#{team.id}", params: { image: file(png) }
      delete "/settings/logos/#{team.id}"
      expect(flash[:notice]).to eq("Boston Testers logo removed.")
      expect([ team.reload.logo.attached?, team.logo_url ]).to eq([ false, nil ])
    end

    it "serves the stored image back" do
      patch "/settings/logos/#{team.id}", params: { image: file(png) }
      get team.reload.logo_url
      expect(response).to have_http_status(:ok)
      expect([ response.media_type, response.body.b ]).to eq([ "image/png", png ])
    end
  end

  describe "bulk upload for a league" do
    let(:json) { { "Accept" => "application/json" } }
    let!(:lal) { create(:team, sport: team.sport, abbreviation: "LAL", name: "Los Angeles Testers") }

    it "explains the format, size and naming convention, and offers the list of exact names" do
      get "/settings"
      expect(response.body).to include("How to prepare your files", "PNG, JPEG, WebP or GIF", "2 MB", "BOS.png", "jaylen-brown.png", "jaylen-brown_BOS.png",
                                       "dusan-markovic.png", "Logos and photos for NBA", "Download the list of exact file names")
      expect(response.body).to include(CGI.escapeHTML(names_settings_images_path(league: "nba", kind: "teams")), CGI.escapeHTML(names_settings_images_path(league: "nba", kind: "players")))
    end

    it "shows how many teams and players in the league already have an image" do
      team.update!(logo_url: "/x")
      create(:player, sport: team.sport, photo_url: "/y")
      create(:player, sport: team.sport)
      get "/settings"
      expect(response.body).to include(%(<b class="text-fg tabular-nums" data-bulk-upload-target="count">1</b> of <span class="tabular-nums">#{Team.count}</span> teams have a logo),
                                       %(<b class="text-fg tabular-nums" data-bulk-upload-target="count">1</b> of <span class="tabular-nums">2</span> players have a photo))
    end

    it "matches many files by name, saves them, and reports each one as JSON with the league's new totals" do
      post "/settings/images", params: { league: "nba", kind: "teams", files: [ file(png, name: "BOS.png"), file(png, name: "lal.jpg"), file(png, name: "zzz.png") ] }, headers: json
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["results"].map { |r| [ r["file"], r["status"], r["target"] ] }).to eq([ [ "BOS.png", "saved", "Boston Testers" ], [ "lal.jpg", "saved", "Los Angeles Testers" ], [ "zzz.png", "skipped", nil ] ])
      expect(body["results"].last["message"]).to match(/No team has the code “zzz”/)
      expect(body["totals"]).to eq({ "with_image" => 2, "total" => 2 })
      expect([ team.reload.logo.attached?, lal.reload.logo.attached? ]).to eq([ true, true ])
    end

    it "does the same for players" do
      player = create(:player, sport: team.sport, first_name: "Jaylen", last_name: "Brown")
      post "/settings/images", params: { league: "nba", kind: "players", files: [ file(png, name: "jaylen-brown.png") ] }, headers: json
      expect(response.parsed_body["results"].first).to include("status" => "saved", "target" => "Jaylen Brown")
      expect(player.reload.photo).to be_attached
    end

    it "refuses an unknown or disabled league, an unknown kind, and an empty request" do
      post "/settings/images", params: { league: "nfl", kind: "teams", files: [ file(png, name: "BOS.png") ] }, headers: json
      expect(response).to have_http_status(:unprocessable_content)
      post "/settings/images", params: { league: "nba", kind: "coaches", files: [ file(png, name: "BOS.png") ] }, headers: json
      expect(response).to have_http_status(:unprocessable_content)
      post "/settings/images", params: { league: "nba", kind: "teams" }, headers: json
      expect(response.parsed_body["error"]).to match(/No files/)
    end

    it "handles at most 50 files per request (the page sends batches of 20)" do
      files = (1..52).map { |i| file(png, name: "T#{i}.png") }
      post "/settings/images", params: { league: "nba", kind: "teams", files: files }, headers: json
      expect(response.parsed_body["results"].size).to eq(50)
    end

    it "downloads the exact names as CSV" do
      get "/settings/images/names", params: { league: "nba", kind: "teams" }
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("nba-teams-file-names.csv")
      expect(response.body).to eq("file_name,name,team,has_image\nBOS.png,Boston Testers,BOS,false\nLAL.png,Los Angeles Testers,LAL,false\n")
    end

    it "tells a non-admin no, as JSON" do
      allow(Rails.configuration.x).to receive(:single_user).and_return(false)
      user = create(:user)
      post session_path, params: { email_address: user.email_address, password: "password123" }
      post "/settings/images", params: { league: "nba", kind: "teams", files: [ file(png, name: "BOS.png") ] }, headers: json
      expect(response).to have_http_status(:forbidden)
      expect(team.reload.logo).not_to be_attached
    end
  end

  describe "who may change images" do
    before { allow(Rails.configuration.x).to receive(:single_user).and_return(false) }

    it "lets an admin" do
      admin = create(:user, :admin)
      post session_path, params: { email_address: admin.email_address, password: "password123" }
      patch "/settings/logos/#{team.id}", params: { image: file(png) }
      expect(team.reload.logo).to be_attached
    end

    it "turns an ordinary user away, hides the image section and still shows About" do
      user = create(:user)
      post session_path, params: { email_address: user.email_address, password: "password123" }
      patch "/settings/logos/#{team.id}", params: { image: file(png) }
      expect(flash[:alert]).to eq("Only an admin can change images.")
      expect(team.reload.logo).not_to be_attached
      get "/settings"
      expect(response.body).to include("About")
      expect(response.body).not_to include("Team logos")
    end

    it "sends a guest to sign in" do
      patch "/settings/logos/#{team.id}", params: { image: file(png) }
      expect(response).to redirect_to(new_session_path)
    end
  end
end
