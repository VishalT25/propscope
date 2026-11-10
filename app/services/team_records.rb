# Win/loss records computed from our own final games (no provider needed).
class TeamRecords
  Result = Data.define(:wins, :losses) do
    def to_s = "#{wins}-#{losses}"
    def pct = (wins + losses).zero? ? nil : BigDecimal(wins) / (wins + losses)
  end

  # results[team_id] = [[date, won?, home?]] oldest first
  def self.call(season:)
    results = Hash.new { |h, k| h[k] = [] }
    Game.final.where(season: season).where.not(home_score: nil, away_score: nil).order(:starts_at).find_each do |g|
      results[g.home_team_id] << [ g.slate_date, g.home_score > g.away_score, true ]
      results[g.away_team_id] << [ g.slate_date, g.away_score > g.home_score, false ]
    end
    new(results)
  end

  def initialize(results) = @results = results

  def record(team_id, venue: nil, before: nil)
    games = @results.fetch(team_id, [])
    games = games.select { |d, _, _| d < before } if before
    games = games.select { |_, _, home| home == (venue == :home) } if venue
    Result.new(wins: games.count { |_, won, _| won }, losses: games.count { |_, won, _| !won })
  end

  # Win percentage before a date; nil until the team has played MIN games (too noisy to call anyone "better").
  MIN = 3
  def pct_before(team_id, date)
    r = record(team_id, before: date)
    r.wins + r.losses < MIN ? nil : r.pct
  end

  def last(team_id, count = 5) = @results.fetch(team_id, []).last(count).map { |_, won, _| won }
end
