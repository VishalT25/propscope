# Average allowed per stat, per position bucket, per team, ranked. Computed from our own game logs.
#   rank 1 = allows the LEAST (toughest defence), so the top `tier_size` ranks are "unfavorable" for the bettor
#   and the bottom `tier_size` are "favorable". Tier size is 10 (config) but never more than a third of the league,
#   so a small sample league (the 16-team fixtures) still has a neutral middle.
class DefenseRanker
  Row = Data.define(:team_id, :stat, :position, :avg_allowed, :rank, :tier)

  def self.call(**) = new(**).call

  def initialize(season:, now: Time.current, tier_size: Rails.configuration.x.defense_tier_size)
    @season, @now, @tier_size = season, now, tier_size
  end

  # Returns the rows it computed, and upserts them into defense_ranks.
  def call
    rows = rank(averages)
    persist(rows)
    rows
  end

  private

  # { [team_id, position, stat] => avg allowed per game by that position group }
  def averages
    per_game = Hash.new { |h, k| h[k] = [] }
    sql = <<~SQL.squish
      SELECT l.opponent_team_id AS team_id, split_part(p.position, '-', 1) AS bucket, l.game_id,
             SUM(l.points) AS points, SUM(l.rebounds) AS rebounds, SUM(l.assists) AS assists,
             SUM(l.threes_made) AS threes_made, SUM(l.points + l.rebounds + l.assists) AS pra
      FROM player_game_logs l JOIN players p ON p.id = l.player_id
      WHERE l.season = ? AND l.minutes > 0 AND p.position IS NOT NULL AND p.position <> ''
      GROUP BY l.opponent_team_id, bucket, l.game_id
    SQL
    PlayerGameLog.connection.select_all(PlayerGameLog.sanitize_sql_array([ sql, Integer(@season) ])).each do |r|
      StatCatalog::DEFENSE_STATS.each { |stat| per_game[[ r["team_id"], r["bucket"], stat ]] << r[stat].to_i }
    end
    # "all" = everything a team allowed per game to every player (the Overall tab)
    all_sql = <<~SQL.squish
      SELECT l.opponent_team_id AS team_id, l.game_id, SUM(l.points) AS points, SUM(l.rebounds) AS rebounds, SUM(l.assists) AS assists,
             SUM(l.threes_made) AS threes_made, SUM(l.points + l.rebounds + l.assists) AS pra
      FROM player_game_logs l WHERE l.season = ? AND l.minutes > 0 GROUP BY l.opponent_team_id, l.game_id
    SQL
    PlayerGameLog.connection.select_all(PlayerGameLog.sanitize_sql_array([ all_sql, Integer(@season) ])).each do |r|
      StatCatalog::DEFENSE_STATS.each { |stat| per_game[[ r["team_id"], "all", stat ]] << r[stat].to_i }
    end
    per_game.transform_values { |v| (BigDecimal(v.sum) / v.size).round(2) }
  end

  def rank(avgs)
    avgs.group_by { |(_, position, stat), _| [ position, stat ] }.flat_map do |(position, stat), entries|
      sorted = entries.sort_by { |(team_id, *), avg| [ avg, team_id ] }
      size = [ @tier_size, sorted.size / 3 ].min
      sorted.each_with_index.map do |((team_id, _, _), avg), i|
        rank = i + 1
        tier = if rank <= size then "unfavorable" elsif rank > sorted.size - size then "favorable" else "neutral" end
        Row.new(team_id: team_id, stat: stat, position: position, avg_allowed: avg, rank: rank, tier: tier)
      end
    end
  end

  def persist(rows)
    return if rows.empty?

    DefenseRank.upsert_all(
      rows.map { |r| r.to_h.merge(season: @season, computed_at: @now) },
      unique_by: %i[team_id stat position season]
    )
  end
end
