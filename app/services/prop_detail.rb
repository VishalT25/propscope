# Everything the prop detail page shows for one (market, side). Reads only our own tables.
class PropDetail
  WINDOWS = PropsQuery::WINDOWS
  DEFAULT_WINDOW = "l10".freeze
  SUPPORT = {
    "minutes" => [ "Minutes", ->(l) { l.minutes.to_d } ],
    "fga" => [ "FG attempts", ->(l) { l.stats["fga"].to_i } ],
    "fg3a" => [ "3PT attempts", ->(l) { l.stats["fg3a"].to_i } ],
    "fta" => [ "FT attempts", ->(l) { l.stats["fta"].to_i } ],
    "fouls" => [ "Fouls", ->(l) { l.fouls } ],
    "turnovers" => [ "Turnovers", ->(l) { l.turnovers } ]
  }.freeze

  Bar = Data.define(:date, :label, :value, :outcome, :closing_line, :outcome_vs_closing)
  Summary = Data.define(:window, :hits, :misses, :pushes, :rate, :closing_hits, :closing_n, :closing_rate, :mean, :median, :avg_closing_line)
  SupportSeries = Data.define(:key, :label, :bars, :mean, :median)
  BookRow = Data.define(:bookmaker, :over, :under, :enabled, :best)
  Streak = Data.define(:hits, :count, :average)
  Detail = Data.define(:market, :side, :player, :game, :team, :opponent, :price, :opposite_price, :books, :lines, :window, :bars, :summary,
                       :support, :support_averages, :defense, :defense_dpos, :defense_tabs, :tier, :history, :history_position, :history_all, :movement,
                       :movement_side, :stat_tabs, :streak, :rates, :prediction)

  def self.call(**) = new(**).call

  def initialize(market:, side:, window: DEFAULT_WINDOW, support: "minutes", position: nil, dpos: nil, all: false, move: nil, bookmaker_ids: nil, now: Time.current)
    @market, @side = market, side
    @window = WINDOWS.include?(window.to_s) ? window.to_s : DEFAULT_WINDOW
    @support = SUPPORT.key?(support.to_s) ? support.to_s : "minutes"
    @position = position
    @dpos = %w[all G F C].include?(dpos.to_s) ? dpos.to_s : "all"
    @all = all
    @move_side = %w[over under].include?(move.to_s) ? move.to_s : side
    @bookmaker_ids = bookmaker_ids
    @now = now
  end

  def call
    game = @market.game
    player = @market.player
    team = player.team
    opponent = game.home_team_id == team&.id ? game.away_team : game.home_team
    stat = StatCatalog.for_market(@market.market_type)
    logs = player.game_logs.played.to_a
    closing = ClosingLines.call(player_ids: [ player.id ])
    window_logs = window_logs(logs, stat, opponent)
    bars = bars_for(window_logs, stat, closing)
    bucket = StatCatalog.position_bucket(player.position)
    defense_tabs = DefenseRank.where(team_id: opponent.id, stat: stat.defense_stat, season: game.season).index_by(&:position)
    defense = defense_tabs["all"] # the headline matchup is the team-level rank; the position tabs show the splits

    Detail.new(
      market: @market, side: @side, player: player, game: game, team: team, opponent: opponent,
      price: prices[[ @market.id, @side ]], opposite_price: prices[[ @market.id, opposite ]],
      books: book_rows, lines: sibling_lines, window: @window, bars: bars, summary: summarize(bars),
      support: support_series(window_logs), support_averages: support_averages(window_logs), defense: defense, defense_dpos: @dpos, defense_tabs: defense_tabs, tier: defense && (@side == "under" ? PropsQuery::INVERT.fetch(defense.tier) : defense.tier),
      history: History.call(market: @market, opponent: opponent, position: history_position(player), closing_for: ClosingLines, side: @side, all: @all),
      history_position: history_position(player), history_all: @all, movement: LineMovement.call(market: @market, side: @move_side, bookmaker_ids: @bookmaker_ids),
      movement_side: @move_side, stat_tabs: stat_tabs, streak: streak(logs, stat), rates: PropHitRate.find_by(market_id: @market.id, side: @side),
      prediction: Prediction.find_by(market_id: @market.id, side: @side)
    )
  end

  private

  # One tab per stat the player has a prop for in this game (PTS, REB, AST, 3PM, PRA).
  def stat_tabs
    markets = Market.where(game_id: @market.game_id, player_id: @market.player_id, is_alternate: false).to_a.group_by(&:market_type)
    StatCatalog::ALL.map do |stat|
      candidates = markets[stat.market_type].to_a
      best = BestPrice.for(market_ids: candidates.map(&:id), bookmaker_ids: @bookmaker_ids)
      live = candidates.select { |m| best[[ m.id, @side ]] }
      chosen = live.find { |m| m.id == @market.id } || live.min_by { |m| (m.line - @market.line).abs }
      [ stat, chosen ]
    end
  end

  # Consecutive most recent games (all played games, newest first) that cleared this line on this side.
  def streak(logs, stat)
    values = HitRateCalculator.played(HitRateCalculator.game_values(logs, stat))
    run = values.take_while { |gv| HitRateCalculator.outcome(gv.value, @market.line, @side) == true }
    return nil if run.size < 3

    Streak.new(hits: true, count: run.size, average: (run.sum { |gv| gv.value.to_d } / run.size).round(1))
  end

  def support_averages(window_logs)
    SUPPORT.transform_values do |(_, extractor)|
      values = window_logs.map { |log, _| extractor.call(log).to_d }
      values.empty? ? nil : (values.sum / values.size).round(1)
    end
  end

  def opposite = @side == "over" ? "under" : "over"

  def prices = @prices ||= BestPrice.for(market_ids: [ @market.id ], bookmaker_ids: @bookmaker_ids)

  # [{ log, value }] newest first, for the chosen window (the same games the hit rate uses).
  def window_logs(logs, stat, opponent)
    by_key = logs.index_by { |l| [ l.game_id ] }
    values = HitRateCalculator.game_values(logs, stat)
    games = HitRateCalculator.window_games(values, @window, current_season: @market.game.season, opponent_id: opponent.id)
    games.map { |gv| [ by_key.fetch([ gv.game_id ]), gv ] }
  end

  def bars_for(window_logs, stat, closing)
    window_logs.reverse.map do |log, gv|
      cl = closing[[ @market.player_id, @market.market_type, log.game_id ]]
      opponent = log.opponent_team
      Bar.new(date: log.game_date, label: "#{log.home ? 'vs' : '@'} #{opponent.abbreviation}", value: gv.value,
              outcome: HitRateCalculator.outcome(gv.value, @market.line, @side), closing_line: cl,
              outcome_vs_closing: cl && HitRateCalculator.outcome(gv.value, cl, @side))
    end
  end

  def summarize(bars)
    outcomes = bars.map(&:outcome)
    decided = bars.select { |b| b.closing_line && !b.outcome_vs_closing.nil? }
    values = bars.map(&:value).sort
    closings = bars.filter_map(&:closing_line)
    hits = outcomes.count(true)
    misses = outcomes.count(false)
    Summary.new(
      window: @window, hits: hits, misses: misses, pushes: outcomes.count(nil), rate: (hits + misses).zero? ? nil : (BigDecimal(hits) * 100 / (hits + misses)).round(2),
      closing_hits: decided.count(&:outcome_vs_closing), closing_n: decided.size,
      closing_rate: decided.empty? ? nil : (BigDecimal(decided.count(&:outcome_vs_closing)) * 100 / decided.size).round(2),
      mean: mean(values), median: median(values), avg_closing_line: closings.empty? ? nil : (closings.sum / closings.size).round(2)
    )
  end

  def support_series(window_logs)
    label, extractor = SUPPORT.fetch(@support)
    bars = window_logs.reverse.map { |log, _| Bar.new(date: log.game_date, label: "#{log.home ? 'vs' : '@'} #{log.opponent_team.abbreviation}", value: extractor.call(log), outcome: nil, closing_line: nil, outcome_vs_closing: nil) }
    values = bars.map(&:value).sort
    SupportSeries.new(key: @support, label: label, bars: bars, mean: mean(values), median: median(values))
  end

  # Latest price per book for both sides of THIS line.
  def book_rows
    latest = BestPrice.current_snapshots(market_ids: [ @market.id ])
    books = Bookmaker.where(id: latest.map(&:bookmaker_id).uniq).index_by(&:id)
    best_id = prices[[ @market.id, @side ]]&.bookmaker&.id
    latest.group_by(&:bookmaker_id).map do |book_id, snaps|
      book = books.fetch(book_id)
      by_side = snaps.index_by(&:outcome)
      BookRow.new(bookmaker: book, over: by_side["over"], under: by_side["under"], enabled: @bookmaker_ids.nil? || @bookmaker_ids.include?(book.id), best: book.id == best_id)
    end.sort_by { |r| [ r.enabled ? 0 : 1, -(r.public_send(@side)&.decimal_odds || 0) ] }
  end

  # Other lines for the same player, stat and game ("custom lines").
  def sibling_lines
    markets = Market.where(game_id: @market.game_id, player_id: @market.player_id, market_type: @market.market_type).order(:line).to_a
    best = BestPrice.for(market_ids: markets.map(&:id), bookmaker_ids: @bookmaker_ids)
    markets.filter_map { |m| (price = best[[ m.id, @side ]]) && [ m, price ] }
  end

  def history_position(player) = @position.presence || StatCatalog.position_bucket(player.position)

  def mean(values) = values.empty? ? nil : (values.sum.to_d / values.size).round(2)

  def median(values)
    return nil if values.empty?

    mid = values.size / 2
    (values.size.odd? ? values[mid].to_d : (values[mid - 1].to_d + values[mid]) / 2).round(2)
  end
end
