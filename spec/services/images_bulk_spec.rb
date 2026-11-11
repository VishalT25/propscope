require "rails_helper"

RSpec.describe "Bulk image upload" do
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") }
  let(:sport) { create(:sport) }
  let!(:bos) { create(:team, sport: sport, abbreviation: "BOS", name: "Boston Testers") }
  let!(:lal) { create(:team, sport: sport, abbreviation: "LAL", name: "Los Angeles Testers") }

  after { FileUtils.rm_rf(Dir[File.join(ActiveStorage::Blob.service.root, "*")]) }

  def upload(name, bytes = png)
    tempfile = Tempfile.new([ "up", File.extname(name) ], binmode: true).tap { |f| f.write(bytes); f.rewind }
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: name, type: "image/png")
  end

  describe Images::Resolve do
    def resolve(kind, name) = described_class.new(sport: sport, kind: kind).call(name)

    it "matches a team by its code, in any case and with any extension or folder" do
      expect(resolve("teams", "BOS.png").record).to eq(bos)
      expect(resolve("teams", "lal.WEBP").record).to eq(lal)
      expect(resolve("teams", "logos\\east/Bos.jpeg").record).to eq(bos)
    end

    it "explains a team code that matches nothing" do
      found = resolve("teams", "XYZ.png")
      expect([ found.record, found.error ]).to match([ nil, /No team has the code “XYZ”.*BOS\.png/ ])
    end

    it "matches a player by hyphenated name, ignoring case, accents, punctuation and suffixes" do
      dusan = create(:player, sport: sport, first_name: "Dušan", last_name: "Marković")
      wendell = create(:player, sport: sport, first_name: "Wendell", last_name: "Carter Jr.")
      karl = create(:player, sport: sport, first_name: "Karl-Anthony", last_name: "Towns")
      expect(resolve("players", "dusan-markovic.png").record).to eq(dusan)
      expect(resolve("players", "Dusan-Markovic.JPG").record).to eq(dusan)
      expect(resolve("players", "wendell-carter.png").record).to eq(wendell)
      expect(resolve("players", "wendell-carter-jr.png").record).to eq(wendell)
      expect(resolve("players", "karl-anthony-towns.png").record).to eq(karl)
    end

    it "uses the team code after an underscore only to tell apart players with the same name" do
      a = create(:player, sport: sport, team: bos, first_name: "Jaylen", last_name: "Brown")
      b = create(:player, sport: sport, team: lal, first_name: "Jaylen", last_name: "Brown")
      ambiguous = resolve("players", "jaylen-brown.png")
      expect(ambiguous.record).to be_nil
      expect(ambiguous.error).to match(/2 players are named “jaylen brown” \(BOS, LAL\).*jaylen-brown_BOS\.png/)
      expect(resolve("players", "jaylen-brown_BOS.png").record).to eq(a)
      expect(resolve("players", "jaylen-brown_lal.png").record).to eq(b)
      expect(resolve("players", "jaylen-brown_ZZZ.png").record).to be_nil
    end

    it "does not need the code when the name is unique, even if one is given" do
      only = create(:player, sport: sport, team: bos, first_name: "Solo", last_name: "Player")
      expect(resolve("players", "solo-player_BOS.png").record).to eq(only)
    end

    it "explains an unknown player, and never reaches into another league" do
      other = create(:sport, key: "nfl", name: "NFL")
      create(:player, sport: other, first_name: "Elsewhere", last_name: "Person")
      found = resolve("players", "elsewhere-person.png")
      expect([ found.record, found.error ]).to match([ nil, /No player named “elsewhere person”.*jaylen-brown\.png/ ])
    end
  end

  describe Images::Bulk do
    let(:player) { create(:player, sport: sport, first_name: "Jaylen", last_name: "Brown") }

    it "saves what matches and reports the rest with the reason, one bad file never stopping the others" do
      player
      files = [ upload("BOS.png"), upload("lal.png"), upload("nobody.png"), upload("jaylen-brown.png") ]
      results = described_class.call(sport: sport, kind: "teams", files: files.first(3))
      expect(results.map { |r| [ r.file, r.status ] }).to eq([ [ "BOS.png", :saved ], [ "lal.png", :saved ], [ "nobody.png", :skipped ] ])
      expect(results.first.target).to eq("Boston Testers")
      expect(results.last.message).to match(/No team has the code “nobody”/)
      expect([ bos.reload.logo.attached?, lal.reload.logo.attached? ]).to eq([ true, true ])

      players = described_class.call(sport: sport, kind: "players", files: [ files.last ])
      expect([ players.first.status, players.first.target ]).to eq([ :saved, "Jaylen Brown" ])
      expect(player.reload.photo).to be_attached
    end

    it "says why a matched file was refused, and still names who it was for" do
      result = described_class.call(sport: sport, kind: "teams", files: [ upload("BOS.png", "not an image") ]).first
      expect([ result.status, result.target, result.message ]).to match([ :skipped, "Boston Testers", /not a PNG, JPEG, WebP or GIF/ ])
      expect(bos.reload.logo).not_to be_attached
    end

    it "replaces an existing image" do
      described_class.call(sport: sport, kind: "teams", files: [ upload("BOS.png") ])
      first = bos.reload.logo_url
      described_class.call(sport: sport, kind: "teams", files: [ upload("BOS.png", png + "0") ])
      expect(bos.reload.logo_url).not_to eq(first)
    end

    it "copes with something that is not an upload" do
      result = described_class.call(sport: sport, kind: "teams", files: [ "BOS.png" ]).first
      expect(result.status).to eq(:skipped)
    end
  end

  describe Images::ExpectedNames do
    it "lists a team code file for every team, with whether it has a logo yet" do
      bos.update!(logo_url: "/x")
      rows = described_class.call(sport: sport, kind: "teams")
      expect(rows).to eq([ %w[file_name name team has_image], [ "BOS.png", "Boston Testers", "BOS", "true" ], [ "LAL.png", "Los Angeles Testers", "LAL", "false" ] ])
    end

    it "lists players by hyphenated name, adding the team code only where two share a name" do
      create(:player, sport: sport, team: bos, first_name: "Jaylen", last_name: "Brown")
      create(:player, sport: sport, team: lal, first_name: "Jaylen", last_name: "Brown")
      create(:player, sport: sport, team: bos, first_name: "Dušan", last_name: "Marković")
      names = described_class.call(sport: sport, kind: "players").drop(1).map(&:first)
      expect(names).to contain_exactly("jaylen-brown_BOS.png", "jaylen-brown_LAL.png", "dusan-markovic.png")
    end

    it "writes CSV, quoting what needs it" do
      csv = described_class.to_csv([ %w[a b], [ "x, y", %(say "hi") ] ])
      expect(csv).to eq(%(a,b\n"x, y","say ""hi"""\n))
    end

    it "gives names that the matcher accepts, for every player" do
      create(:player, sport: sport, team: bos, first_name: "Jaylen", last_name: "Brown")
      create(:player, sport: sport, team: lal, first_name: "Jaylen", last_name: "Brown")
      create(:player, sport: sport, team: lal, first_name: "Wendell", last_name: "Carter Jr.")
      resolver = Images::Resolve.new(sport: sport, kind: "players")
      described_class.call(sport: sport, kind: "players").drop(1).each do |file_name, name, *|
        expect(resolver.call(file_name).record&.full_name).to eq(name), "#{file_name} should find #{name}"
      end
    end
  end
end
