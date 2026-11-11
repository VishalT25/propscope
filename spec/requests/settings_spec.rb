require "rails_helper"

RSpec.describe "Settings and About" do
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") }
  let(:team) { create(:team, name: "Boston Testers", abbreviation: "BOS") }

  def file(bytes, name: "logo.png", type: "image/png")
    path = Rails.root.join("tmp", "upload-#{SecureRandom.hex(4)}-#{name}")
    File.binwrite(path, bytes)
    Rack::Test::UploadedFile.new(path, type)
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
