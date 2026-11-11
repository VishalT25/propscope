require "rails_helper"

RSpec.describe Images::Attach do
  let(:png) { Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") }

  after { FileUtils.rm_rf(Dir[File.join(ActiveStorage::Blob.service.root, "*")]) } # the test disk service keeps real files (but not the tracked .keep)

  let(:team) { create(:team) }
  let(:player) { create(:player) }

  # An uploaded file as a controller sees it: the browser's claimed name and type, and the real bytes.
  def upload(bytes, name: "pic.png", type: "image/png")
    tempfile = Tempfile.new([ "upload", File.extname(name) ], binmode: true).tap { |f| f.write(bytes); f.rewind }
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: name, type: type)
  end

  it "stores a PNG as a team's logo and points logo_url at it" do
    described_class.call(record: team, file: upload(png))
    team.reload
    expect(team.logo).to be_attached
    expect(team.logo.content_type).to eq("image/png")
    expect(team.logo_url).to start_with("/rails/active_storage/blobs/proxy/")
    expect(team.logo.download).to eq(png)
  end

  it "stores a player's photo the same way, whatever the file is called" do
    described_class.call(record: player, file: upload(png, name: "../../etc/Evil Name.PNG"))
    expect(player.reload.photo.filename.to_s).to eq("photo-#{player.id}.png")
    expect(player.photo_url).to be_present
  end

  it "recognises JPEG, GIF and WebP by their bytes, not by what the browser says" do
    { "image/jpeg" => "\xFF\xD8\xFF\xE0".b + "x" * 12, "image/gif" => "GIF89a".b + "x" * 12, "image/webp" => "RIFF".b + "\0\0\0\0".b + "WEBP".b + "x" * 8 }.each do |type, bytes|
      team.update!(logo_url: nil)
      described_class.call(record: team, file: upload(bytes, name: "whatever.bin", type: "application/octet-stream"))
      expect(team.reload.logo.content_type).to eq(type)
    end
  end

  it "refuses SVG, HTML and plain text even when they claim to be a PNG" do
    [ %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>), "<html><script>alert(1)</script></html>", "hello" ].each do |body|
      expect { described_class.call(record: team, file: upload(body, name: "x.png", type: "image/png")) }.to raise_error(Images::Attach::Invalid, /not a PNG, JPEG, WebP or GIF/)
    end
    expect([ team.reload.logo.attached?, team.logo_url, ActiveStorage::Blob.count ]).to eq([ false, nil, 0 ])
  end

  it "refuses a file over 2 MB and a missing file" do
    expect { described_class.call(record: team, file: upload(png + ("0" * 2.megabytes))) }.to raise_error(Images::Attach::Invalid, /over 2 MB/)
    expect { described_class.call(record: team, file: nil) }.to raise_error(Images::Attach::Invalid, /Choose an image/)
    expect { described_class.call(record: team, file: "logo.png") }.to raise_error(Images::Attach::Invalid, /Choose an image/)
  end

  it "replaces an earlier upload" do
    described_class.call(record: team, file: upload(png))
    first = team.reload.logo_url
    described_class.call(record: team, file: upload(png + "0"))
    expect(team.reload.logo_url).not_to eq(first)
    expect(ActiveStorage::Attachment.where(record: team).count).to eq(1)
  end

  describe Images::Remove do
    it "removes the upload and the url, so the badge goes back to its monogram" do
      described_class_attach = Images::Attach.call(record: team, file: upload(png))
      expect(described_class_attach.logo).to be_attached
      Images::Remove.call(record: team)
      expect([ team.reload.logo.attached?, team.logo_url ]).to eq([ false, nil ])
    end

    it "also clears a pasted url that was never an upload" do
      player.update!(photo_url: "https://example.test/p.png")
      Images::Remove.call(record: player)
      expect(player.reload.photo_url).to be_nil
    end
  end
end
