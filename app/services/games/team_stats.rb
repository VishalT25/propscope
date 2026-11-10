module Games
  # Team offence (points etc. scored per game) and defence (allowed per game) from our own box scores, ranked.
  #   scored rank 1 = scores the most; allowed rank 1 = allows the fewest (toughest defence).
  class TeamStats
    STATS = { "points" => "Points", "rebounds" => "Rebounds", "assists" => "Assists", "threes_made" => "3-pointers made" }.freeze
    Line = Data.define(:avg, :rank)
    Team = Data.define(:scored, :allowed) # each { stat => Line }

    def self.call(season:) = new(season).call

    def initialize(season) = @season = season

    # => { team_id => Team }
    def call
      scored = averages("team_id")
      allowed = averages("opponent_team_id")
      team_ids = (scored.keys | allowed.keys)
      ranked_scored = rank(scored, :desc)
      ranked_allowed = rank(allowed, :asc)
      team_ids.to_h { |id| [ id, Team.new(scored: ranked_scored[id], allowed: ranked_allowed[id]) ] }
    end

    private

    # { team_id => { stat => avg per game } } summing every player's line in each game first.
    def averages(team_column)
      sums = STATS.keys.map { |s| "SUM(#{s}) AS #{s}" }.join(", ")
      sql = "SELECT #{team_column} AS tid, game_id, #{sums} FROM player_game_logs WHERE season = ? AND minutes > 0 GROUP BY #{team_column}, game_id"
      rows = PlayerGameLog.connection.select_all(PlayerGameLog.sanitize_sql_array([ sql, Integer(@season) ]))
      rows.group_by { |r| r["tid"] }.transform_values do |games|
        STATS.keys.to_h { |s| [ s, (BigDecimal(games.sum { |g| g[s].to_i }) / games.size).round(1) ] }
      end
    end

    def rank(avgs, direction)
      STATS.keys.each_with_object(Hash.new { |h, k| h[k] = {} }) do |stat, out|
        ordered = avgs.sort_by { |id, v| [ direction == :desc ? -v[stat] : v[stat], id ] }
        ordered.each_with_index { |(id, v), i| out[id][stat] = Line.new(avg: v[stat], rank: i + 1) }
      end
    end
  end
end
