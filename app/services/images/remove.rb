module Images
  # Removes an uploaded (or pasted) logo or photo; the badge falls back to its generated monogram.
  class Remove
    def self.call(record:)
      attachment, url_field = Attach::TARGETS.fetch(record.class)
      record.public_send(attachment).purge if record.public_send(attachment).attached?
      record.update!(url_field => nil)
      record
    end
  end
end
