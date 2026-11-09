module Providers
  # BallDontLie: canonical source for teams, players, games and box scores (NBA).
  # Free tier: teams/players/games at 5 req/min. /stats needs a paid (ALL-STAR) key. See docs/providers/ball_dont_lie.md.
  class BallDontLie < Base
    CAPABILITIES = Set[:stats].freeze
    PER_PAGE = 100
    STATUS = { "Final" => "final", "Postponed" => "postponed" }.freeze

    def provider_key = "balldontlie"

    def cost_of(_kind, count = 1) = count # one unit per request; no monthly cap, only a rate limit

    def fetch_teams(sport:)
      parse_teams(request("/teams"))
    end

    def fetch_players(sport:)
      paginate("/players/active").flat_map { |body| parse_players(body) }
    end

    def fetch_events(sport:, from:, to:)
      paginate("/games", "start_date" => from.to_date.iso8601, "end_date" => to.to_date.iso8601).flat_map { |b| parse_events(b) }
    end

    def fetch_odds(**) = raise(NotImplementedError, "BallDontLie does not provide odds")

    def fetch_game_logs(sport:, date:)
      paginate("/stats", "dates[]" => date.to_date.iso8601).flat_map { |body| parse_game_logs(body) }
    end

    def replay(raw)
      body = raw.body
      case raw.endpoint
      when "/teams" then [ :teams, parse_teams(body) ]
      when "/players/active" then [ :players, parse_players(body) ]
      when "/games" then [ :events, parse_events(body) ]
      when "/stats" then [ :game_logs, parse_game_logs(body) ]
      else [ :unknown, [] ]
      end
    end

    # /teams also returns ~59 defunct franchises (blank conference, some reusing abbreviations like WAS). Keep the 30 real ones.
    def parse_teams(body)
      body.fetch("data").select { |t| t["conference"].to_s.strip.present? }.map do |t|
        Dto::Team.new(provider: provider_key, external_id: t["id"].to_s, abbreviation: t["abbreviation"], name: t["full_name"],
                      city: t["city"], conference: t["conference"], division: t["division"])
      end
    end

    def parse_players(body)
      body.fetch("data").map do |p|
        Dto::Player.new(provider: provider_key, external_id: p["id"].to_s, first_name: p["first_name"], last_name: p["last_name"],
                        position: p["position"].presence, team: team_ref(p["team"]))
      end
    end

    def parse_events(body)
      body.fetch("data").map do |g|
        Dto::Event.new(
          provider: provider_key, external_id: g["id"].to_s,
          home_team: team_ref(g["home_team"]), away_team: team_ref(g["visitor_team"]),
          starts_at: parse_time(g["datetime"] || g["date"]), status: STATUS.fetch(g["status"].to_s, status_for(g)),
          home_score: g["home_team_score"].presence, away_score: g["visitor_team_score"].presence, season: g["season"]
        )
      end
    end

    def parse_game_logs(body)
      body.fetch("data").map do |s|
        game = s.fetch("game")
        team_id = s.dig("team", "id")
        home = team_id == game["home_team_id"]
        Dto::GameLog.new(
          provider: provider_key, game_external_id: game["id"].to_s, player_external_id: s.dig("player", "id").to_s,
          player_name: "#{s.dig('player', 'first_name')} #{s.dig('player', 'last_name')}".strip,
          team_external_id: team_id.to_s, opponent_team_external_id: (home ? game["visitor_team_id"] : game["home_team_id"]).to_s,
          game_date: Date.iso8601(game["date"]), home: home, minutes: parse_minutes(s["min"]),
          points: s["pts"].to_i, rebounds: s["reb"].to_i, assists: s["ast"].to_i, threes_made: s["fg3m"].to_i,
          steals: s["stl"].to_i, blocks: s["blk"].to_i, turnovers: s["turnover"].to_i, fouls: s["pf"].to_i,
          stats: s.slice("fgm", "fga", "fg3a", "ftm", "fta", "oreb", "dreb", "plus_minus")
        )
      end
    end

    private

    def team_ref(t)
      return nil unless t

      Dto::TeamRef.new(external_id: t["id"].to_s, name: t["full_name"], abbreviation: t["abbreviation"])
    end

    def status_for(game)
      game["status"].to_s.match?(/\A\d{4}-/) ? "scheduled" : (game["status"].to_s.empty? ? "scheduled" : "in_progress")
    end

    # "34:12", "34", "", nil, "00" => decimal minutes; 0 means DNP.
    def parse_minutes(value)
      str = value.to_s.strip
      return BigDecimal("0") if str.empty?

      mins, secs = str.split(":")
      (BigDecimal(mins.to_i) + (BigDecimal(secs.to_i) / 60)).round(2)
    end

    def paginate(path, params = {})
      bodies = []
      cursor = nil
      loop do
        body = request(path, params.merge("per_page" => PER_PAGE, **(cursor ? { "cursor" => cursor } : {})))
        bodies << body
        cursor = body.dig("meta", "next_cursor")
        break if cursor.blank? || body["data"].blank?
      end
      bodies
    end
  end
end
