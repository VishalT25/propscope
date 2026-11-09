module Ingest
  # Upserts canonical teams, players and games (from the canonical provider). Safe to run repeatedly.
  class ReferenceData
    Result = Data.define(:teams, :players, :games, :skipped)

    def self.call(**) = new(**).call

    def initialize(teams: [], players: [], events: [], sport: Sport.nba)
      @teams, @players, @events, @sport = teams, players, events, sport
    end

    def call
      skipped = 0
      @teams.each { |dto| upsert_team(dto) }
      @players.each { |dto| skipped += 1 unless upsert_player(dto) }
      games = @events.count { |dto| upsert_game(dto) || (skipped += 1 and false) }
      Result.new(teams: @teams.size, players: @players.size, games: games, skipped: skipped)
    end

    private

    def upsert_team(dto)
      team = ExternalId.lookup(dto.provider, "team", dto.external_id) ||
             @sport.teams.find_or_initialize_by(abbreviation: dto.abbreviation)
      team.update!(name: dto.name, city: dto.city, conference: dto.conference.presence, division: dto.division.presence)
      ExternalId.register!(dto.provider, "team", dto.external_id, team)
    end

    def upsert_player(dto)
      team = dto.team && ExternalId.lookup(dto.provider, "team", dto.team.external_id)
      player = ExternalId.lookup(dto.provider, "player", dto.external_id) || @sport.players.new
      player.update!(first_name: dto.first_name, last_name: dto.last_name, position: dto.position, team: team)
      ExternalId.register!(dto.provider, "player", dto.external_id, player)
    end

    def upsert_game(dto)
      home = ExternalId.lookup(dto.provider, "team", dto.home_team&.external_id)
      away = ExternalId.lookup(dto.provider, "team", dto.away_team&.external_id)
      return false unless home && away && dto.starts_at

      game = ExternalId.lookup(dto.provider, "game", dto.external_id) || @sport.games.new
      game.assign_attributes(home_team: home, away_team: away, starts_at: dto.starts_at, season: dto.season,
                             status: dto.status, home_score: dto.home_score, away_score: dto.away_score)
      game.slate_date = dto.starts_at.in_time_zone(Game::SLATE_ZONE).to_date
      existing = @sport.games.where(home_team: home, away_team: away, slate_date: game.slate_date).where.not(id: game.id).first
      game = existing.tap { |g| g.assign_attributes(game.attributes.slice("starts_at", "season", "status", "home_score", "away_score")) } if existing
      game.save!
      ExternalId.register!(dto.provider, "game", dto.external_id, game)
      true
    end
  end
end
