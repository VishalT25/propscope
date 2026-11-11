module Images
  # Saves many uploaded files for one league and kind (teams or players). Each file is matched by name (Images::Resolve), checked and
  # stored (Images::Attach). One bad file never stops the others; every file gets a result with the reason when it was skipped.
  class Bulk
    Result = Data.define(:file, :status, :target, :message) # status: :saved or :skipped

    def self.call(**) = new(**).call

    def initialize(sport:, kind:, files:)
      @files = files
      @resolver = Resolve.new(sport: sport, kind: kind)
    end

    def call = @files.map { |file| process(file) }

    private

    def process(file)
      name = file.respond_to?(:original_filename) ? file.original_filename.to_s : "(unnamed file)"
      found = @resolver.call(name)
      return Result.new(name, :skipped, nil, found.error) unless found.record

      Attach.call(record: found.record, file: file)
      Result.new(name, :saved, label(found.record), nil)
    rescue Attach::Invalid => e
      Result.new(name, :skipped, found&.record && label(found.record), e.message)
    end

    def label(record) = record.respond_to?(:full_name) ? record.full_name : record.name
  end
end
