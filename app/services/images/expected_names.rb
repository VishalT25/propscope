module Images
  # The exact file names the bulk upload expects for a league: one CSV row per team or player, so nobody has to guess.
  class ExpectedNames
    HEADER = %w[file_name name team has_image].freeze

    def self.call(**) = new(**).call

    def initialize(sport:, kind:)
      @sport = sport
      @kind = kind.to_s
    end

    # An array of rows (arrays of strings), header first.
    def call = [ HEADER ] + (@kind == "teams" ? team_rows : player_rows)

    def self.to_csv(rows) = rows.map { |row| row.map { |f| quote(f) }.join(",") }.join("\n") + "\n"

    def self.quote(value)
      s = value.to_s
      s.match?(/[",\n]/) ? %("#{s.gsub('"', '""')}") : s
    end

    private

    def team_rows = Team.where(sport: @sport).order(:abbreviation).map { |t| [ "#{t.abbreviation}.png", t.name, t.abbreviation, t.logo_url.present?.to_s ] }

    def player_rows
      players = Player.where(sport: @sport).includes(:team).order(:last_name, :first_name).to_a
      shared = players.group_by(&:normalized_name).select { |_, group| group.size > 1 }.keys
      players.map do |p|
        stem = p.normalized_name.tr(" ", "-")
        stem += "_#{p.team.abbreviation}" if shared.include?(p.normalized_name) && p.team
        [ "#{stem}.png", p.full_name, p.team&.abbreviation.to_s, p.photo_url.present?.to_s ]
      end
    end
  end
end
