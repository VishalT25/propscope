module Games
  # One day's slate as cards: teams with records, lines with best price, hit strips. Reads our tables only.
  class Board
    Card = Data.define(:game, :lines, :strips, :home_record, :away_record)

    def self.call(**) = new(**).call

    def initialize(date:, query: nil, bookmaker_ids: nil)
      @date, @query, @bookmaker_ids = date, query.to_s.strip.downcase.presence, bookmaker_ids
    end

    def call
      games = Game.where(slate_date: @date).includes(:home_team, :away_team).order(:starts_at).to_a
      games = games.select { |g| [ g.home_team, g.away_team ].any? { |t| [ t.name, t.abbreviation ].any? { |n| n.downcase.include?(@query) } } } if @query
      return [] if games.empty?

      records = TeamRecords.call(season: games.first.season)
      games.map do |g|
        lines = Lines.call(game: g, bookmaker_ids: @bookmaker_ids)
        Card.new(game: g, lines: lines, strips: HitStrips.call(game: g, lines: lines),
                 home_record: records.record(g.home_team_id, before: g.slate_date), away_record: records.record(g.away_team_id, before: g.slate_date))
      end
    end

    # Today (US Eastern) and the next six days, with how many games each has.
    def self.dates(today: Time.current.in_time_zone(Game::SLATE_ZONE).to_date)
      counts = Game.where(slate_date: today..today + 6).group(:slate_date).count
      (today..today + 6).map { |d| [ d, counts.fetch(d, 0) ] }
    end
  end
end
