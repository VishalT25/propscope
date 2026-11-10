class GamesController < PublicController
  TABS = %w[odds insights matchup].freeze

  def index
    @date = parse_date(params[:date])
    @query = params[:q].to_s.strip.presence
    @dates = Games::Board.dates
    @cards = Games::Board.call(date: @date, query: @query, bookmaker_ids: enabled_bookmaker_ids)
  end

  def show
    @game = Game.includes(:home_team, :away_team).find(params[:id])
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "odds"
    case @tab
    when "odds" then load_odds
    when "insights" then @feed = Insights::Feed.call(filters: { game_id: @game.id, page: params[:page] }, bookmaker_ids: enabled_bookmaker_ids)
    when "matchup" then load_matchup
    end
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    Time.current.in_time_zone(Game::SLATE_ZONE).to_date
  end

  def load_odds
    @lines = Games::Lines.call(game: @game, bookmaker_ids: enabled_bookmaker_ids)
    @strips = Games::HitStrips.call(game: @game, lines: @lines)
    filters = PropsQuery::Filters.from_params(game_ids: [ @game.id ], sort: "l10", dir: "desc")
    rows = PropsQuery.call(filters: filters, bookmaker_ids: enabled_bookmaker_ids, now: @game.starts_at - 1.day, paginate: false).rows
    @props = rows.group_by { |r| r.market.market_type }.transform_values { |rs| rs.group_by(&:market).map { |market, sides| [ market, sides.index_by(&:side) ] } }
  end

  def load_matchup
    stats = Games::TeamStats.call(season: @game.season)
    records = TeamRecords.call(season: @game.season)
    @stats = stats
    @records = [ @game.home_team, @game.away_team ].to_h do |t|
      [ t.id, { overall: records.record(t.id, before: @game.slate_date), home: records.record(t.id, venue: :home, before: @game.slate_date),
                away: records.record(t.id, venue: :away, before: @game.slate_date), form: records.last(t.id, 5) } ]
    end
  end
end
