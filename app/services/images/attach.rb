module Images
  # Stores an uploaded picture as a team's logo or a player's photo and points the record's logo_url / photo_url at it, so every
  # badge on the site picks it up with no extra queries. The file is checked by its own bytes, not by the name or type the browser
  # claims: PNG, JPEG, WebP or GIF only (SVG is refused because it can carry script), up to 2 MB. The stored name is generated.
  class Attach
    class Invalid < StandardError; end

    MAX_BYTES = 2.megabytes
    TARGETS = { Team => %i[logo logo_url], Player => %i[photo photo_url] }.freeze
    EXTENSIONS = { "image/png" => "png", "image/jpeg" => "jpg", "image/gif" => "gif", "image/webp" => "webp" }.freeze

    def self.call(**) = new(**).call

    def initialize(record:, file:)
      @record = record
      @file = file
      @attachment, @url_field = TARGETS.fetch(record.class)
    end

    def call
      raise Invalid, "Choose an image first." unless @file.respond_to?(:tempfile)
      raise Invalid, "That file is over 2 MB." if @file.size > MAX_BYTES

      type = detect_type or raise Invalid, "That is not a PNG, JPEG, WebP or GIF image."
      blob = @file.tempfile.tap(&:rewind).then do |io|
        ActiveStorage::Blob.create_and_upload!(io: io, filename: "#{@attachment}-#{@record.id}.#{EXTENSIONS.fetch(type)}", content_type: type, identify: false)
      end
      @record.public_send(@attachment).attach(blob)
      @record.update!(@url_field => Rails.application.routes.url_helpers.rails_storage_proxy_path(blob, only_path: true))
      @record
    end

    private

    # The type according to the first bytes of the file.
    def detect_type
      head = @file.tempfile.tap(&:rewind).read(12).to_s.b
      @file.tempfile.rewind
      if head.start_with?("\x89PNG\r\n\x1A\n".b) then "image/png"
      elsif head.start_with?("\xFF\xD8\xFF".b) then "image/jpeg"
      elsif head.start_with?("GIF87a".b, "GIF89a".b) then "image/gif"
      elsif head.bytesize == 12 && head.byteslice(0, 4) == "RIFF".b && head.byteslice(8, 4) == "WEBP".b then "image/webp"
      end
    end
  end
end
