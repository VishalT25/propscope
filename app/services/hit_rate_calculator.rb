# Pure Ruby: how often did a player clear a line? Windows: L5, L10, L20, H2H, season, previous season.
#   * DNP games (0 minutes) are excluded everywhere.
#   * Pushes (stat exactly on the line) are excluded from the denominator and counted separately.
#   * H2H = games against this opponent in the current and previous season.
class HitRateCalculator
  WINDOWS = %i[l5 l10 l20 h2h season prev_season].freeze
  RECENT = { l5: 5, l10: 10, l20: 20 }.freeze

  GameValue = Data.define(:date, :season, :opponent_id, :value, :minutes, :game_id) do
    def initialize(game_id: nil, **rest) = super
  end

  Window = Data.define(:hits, :misses, :pushes) do
    def n = hits + misses
    def rate = n.zero? ? nil : (BigDecimal(hits) * 100 / n).round(2)
  end

  Result = Data.define(:line, :side, :windows, :mean, :median)

  def self.call(**) = new(**).call

  # Builds GameValues from PlayerGameLog rows for a given stat.
  def self.game_values(logs, stat)
    logs.map { |l| GameValue.new(date: l.game_date, season: l.season, opponent_id: l.opponent_team_id, value: stat.value(l), minutes: l.minutes, game_id: l.game_id) }
  end

  # Per-game hit (true) / miss (false) / push (nil) for the last `count` played games, oldest first (for the bar).
  def self.outcomes(games:, line:, side:, count: 10)
    played(games).first(count).reverse.map { |g| outcome(g.value, BigDecimal(line.to_s), side) }
  end

  def self.played(games) = games.reject { |g| g.minutes.to_d.zero? }.sort_by { |g| [ g.date, g.season ] }.reverse

  def self.outcome(value, line, side)
    cmp = value <=> line
    return nil if cmp.zero?

    side.to_s == "over" ? cmp.positive? : cmp.negative?
  end

  def initialize(games:, line:, side:, current_season:, opponent_id: nil)
    @games = self.class.played(games)
    @line = BigDecimal(line.to_s)
    @side = side.to_s
    @season = current_season
    @opponent_id = opponent_id
    raise ArgumentError, "side must be over or under" unless %w[over under].include?(@side)
  end

  def call
    groups = RECENT.transform_values { |n| @games.first(n) }
    groups[:season] = @games.select { |g| g.season == @season }
    groups[:prev_season] = @games.select { |g| g.season == @season - 1 }
    groups[:h2h] = @opponent_id ? @games.select { |g| g.opponent_id == @opponent_id && [ @season, @season - 1 ].include?(g.season) } : []
    windows = WINDOWS.index_with { |w| tally(groups.fetch(w)) }
    values = groups[:l10].map(&:value).sort
    Result.new(line: @line, side: @side, windows: windows, mean: mean(values), median: median(values))
  end

  private

  def tally(games)
    outcomes = games.map { |g| self.class.outcome(g.value, @line, @side) }
    Window.new(hits: outcomes.count(true), misses: outcomes.count(false), pushes: outcomes.count(nil))
  end

  def mean(values) = values.empty? ? nil : (BigDecimal(values.sum) / values.size).round(2)

  def median(values)
    return nil if values.empty?

    mid = values.size / 2
    (values.size.odd? ? BigDecimal(values[mid]) : (BigDecimal(values[mid - 1]) + values[mid]) / 2).round(2)
  end
end
