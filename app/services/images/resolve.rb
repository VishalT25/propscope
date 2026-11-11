module Images
  # Works out which team or player an uploaded file is for, from its file name alone. The convention (also shown on Settings):
  #   teams    the team code:                       BOS.png   (any case)
  #   players  the name, words joined by hyphens:   jaylen-brown.png
  #            accents, punctuation and Jr/Sr/II/III don't matter (dusan-markovic.png, wendell-carter.png)
  #            two players with one name: add the team code after an underscore:   jaylen-brown_BOS.png
  class Resolve
    Found = Data.define(:record, :error)

    def initialize(sport:, kind:)
      @sport = sport
      @kind = kind.to_s
    end

    def call(filename)
      stem = File.basename(filename.to_s.tr("\\", "/"), ".*") # a folder upload sends paths; a file may carry any extension
      return Found.new(nil, "That file has no name to match.") if stem.blank?

      @kind == "teams" ? team(stem) : player(stem)
    end

    private

    def team(stem)
      record = Team.where(sport: @sport).find_by("lower(abbreviation) = ?", stem.downcase)
      record ? Found.new(record, nil) : Found.new(nil, "No team has the code “#{stem}”. Name the file with the team code, like BOS.png.")
    end

    def player(stem)
      name_part, team_code = stem.match(/\A(.+?)_([A-Za-z0-9]{2,5})\z/)&.captures || [ stem, nil ]
      normalized = NameNormalizer.call(name_part)
      return Found.new(nil, "That file has no name to match.") if normalized.blank?

      matches = Player.where(sport: @sport, normalized_name: normalized).includes(:team).to_a
      matches = matches.select { |p| p.team&.abbreviation.to_s.casecmp?(team_code) } if team_code && matches.size > 1
      case matches.size
      when 1 then Found.new(matches.first, nil)
      when 0 then Found.new(nil, "No player named “#{normalized}”. Name the file like jaylen-brown.png.")
      else Found.new(nil, "#{matches.size} players are named “#{normalized}” (#{matches.map { |p| p.team&.abbreviation || '?' }.join(', ')}). Add the team code, like #{name_part.parameterize}_#{matches.first.team&.abbreviation || 'BOS'}.png.")
      end
    end
  end
end
