# The features the model sees for one player in one game. Every value comes from games BEFORE that game, so the same
# code builds training rows (history) and live inputs (tonight) without leaking the answer.
# The feature NAMES are a contract with model_service/app/features.py (a spec keeps them in sync).
class ModelFeatures
  FEATURES = %w[
    mean_l5 mean_l10 mean_l20 mean_season std_l10
    min_l5 min_l10
    fga_l10 fg3a_l10 fta_l10
    is_home rest_days back_to_back
    team_scored_l10 opp_scored_l10 opp_allowed_l10
    games_played
  ].freeze
  MIN_PRIOR_GAMES = 5

  Row = Data.define(:player_id, :game_id, :game_date, :features, :target)

  # Loads everything once; then `features_for` is pure array work.
  def initialize(stat:, logs: PlayerGameLog.played.includes(:game).order(:game_date, :id).to_a)
    @stat = stat
    @by_player = logs.group_by(&:player_id)
    @team_games = build_team_games(logs)
  end

  # Features for `player` playing `team` against `opponent` on `date` (a Date) in `season`. nil if too little history.
  def features_for(player_id:, team_id:, opponent_id:, date:, season:, home:)
    prior = (@by_player[player_id] || []).select { |l| l.game_date < date }
    return nil if prior.size < MIN_PRIOR_GAMES

    values = prior.map { |l| @stat.value(l).to_d }
    this_season = prior.select { |l| l.season == season }
    rest = (date - prior.last.game_date).to_i
    {
      "mean_l5" => mean(values.last(5)), "mean_l10" => mean(values.last(10)), "mean_l20" => mean(values.last(20)),
      "mean_season" => mean(this_season.map { |l| @stat.value(l).to_d }), "std_l10" => std(values.last(10)),
      "min_l5" => mean(prior.last(5).map { |l| l.minutes.to_d }), "min_l10" => mean(prior.last(10).map { |l| l.minutes.to_d }),
      "fga_l10" => stat_mean(prior.last(10), "fga"), "fg3a_l10" => stat_mean(prior.last(10), "fg3a"), "fta_l10" => stat_mean(prior.last(10), "fta"),
      "is_home" => home ? 1.0 : 0.0, "rest_days" => [ rest, 14 ].min.to_f, "back_to_back" => rest == 1 ? 1.0 : 0.0,
      "team_scored_l10" => team_mean(team_id, date, :scored), "opp_scored_l10" => team_mean(opponent_id, date, :scored),
      "opp_allowed_l10" => team_mean(opponent_id, date, :allowed), "games_played" => this_season.size.to_f
    }
  end

  # Every historical (player, game) with enough prior games, for training.
  def training_rows
    @by_player.flat_map do |player_id, logs|
      logs.filter_map do |log|
        f = features_for(player_id: player_id, team_id: log.team_id, opponent_id: log.opponent_team_id, date: log.game_date, season: log.season, home: log.home)
        Row.new(player_id: player_id, game_id: log.game_id, game_date: log.game_date, features: f, target: @stat.value(log)) if f
      end
    end
  end

  private

  # { team_id => [[date, scored, allowed]] oldest first }, from the box scores
  def build_team_games(logs)
    points = Hash.new { |h, k| h[k] = Hash.new(0) } # game_id => { team_id => points }
    dates = {}
    logs.each { |l| points[l.game_id][l.team_id] += l.points; dates[l.game_id] = l.game_date }
    out = Hash.new { |h, k| h[k] = [] }
    points.each do |game_id, by_team|
      next unless by_team.size == 2

      (a, pa), (b, pb) = by_team.to_a
      out[a] << [ dates[game_id], pa, pb ]
      out[b] << [ dates[game_id], pb, pa ]
    end
    out.each_value { |games| games.sort_by!(&:first) }
  end

  def team_mean(team_id, date, which)
    recent = (@team_games[team_id] || []).select { |d, _, _| d < date }.last(10)
    return nil if recent.empty?

    idx = which == :scored ? 1 : 2
    (recent.sum { |g| g[idx] }.to_d / recent.size).round(3).to_f
  end

  def stat_mean(logs, key)
    vals = logs.filter_map { |l| l.stats[key] }
    vals.empty? ? nil : (vals.sum.to_d / vals.size).round(3).to_f
  end

  def mean(values) = values.empty? ? nil : (values.sum / values.size).round(3).to_f

  def std(values)
    return nil if values.size < 3

    m = values.sum / values.size
    Math.sqrt((values.sum { |v| (v - m)**2 } / (values.size - 1)).to_f).round(3)
  end
end
