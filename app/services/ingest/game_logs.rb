module Ingest
  # Idempotent upsert of box-score rows keyed on (player, game).
  class GameLogs
    Result = Data.define(:upserted, :skipped)

    def self.call(**) = new(**).call

    def initialize(logs:)
      @logs = logs
    end

    def call
      lookups = preload
      rows = @logs.filter_map { |dto| row_for(dto, lookups) }
      PlayerGameLog.upsert_all(rows, unique_by: %i[player_id game_id]) if rows.any?
      Result.new(upserted: rows.size, skipped: @logs.size - rows.size)
    end

    private

    # One query per entity type instead of four per row.
    def preload
      by_provider = @logs.group_by(&:provider)
      players = {}
      games = {}
      teams = {}
      by_provider.each do |provider, logs|
        players[provider] = ExternalId.internal_ids(provider, "player", logs.map(&:player_external_id))
        games[provider] = ExternalId.internal_ids(provider, "game", logs.map(&:game_external_id))
        teams[provider] = ExternalId.internal_ids(provider, "team", logs.flat_map { |l| [ l.team_external_id, l.opponent_team_external_id ] })
      end
      seasons = Game.where(id: games.values.flat_map(&:values)).pluck(:id, :season).to_h
      { players: players, games: games, teams: teams, seasons: seasons }
    end

    def row_for(dto, l)
      player_id = l[:players][dto.provider][dto.player_external_id]
      game_id = l[:games][dto.provider][dto.game_external_id]
      team_id = l[:teams][dto.provider][dto.team_external_id]
      opponent_id = l[:teams][dto.provider][dto.opponent_team_external_id]
      return nil unless player_id && game_id && team_id && opponent_id

      { player_id: player_id, game_id: game_id, team_id: team_id, opponent_team_id: opponent_id, game_date: dto.game_date,
        season: l[:seasons][game_id], home: dto.home, minutes: dto.minutes, points: dto.points, rebounds: dto.rebounds,
        assists: dto.assists, threes_made: dto.threes_made, steals: dto.steals, blocks: dto.blocks,
        turnovers: dto.turnovers, fouls: dto.fouls, stats: dto.stats }
    end
  end
end
