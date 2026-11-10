class InsightsController < PublicController
  def index
    @filters = params.permit(:game_id, :team_id, :q, :market_type, :page).to_h.symbolize_keys
    @feed = Insights::Feed.call(filters: @filters, bookmaker_ids: enabled_bookmaker_ids)
    @games = PropsQuery.upcoming_games
    @teams = Team.where(id: @games.flat_map { |g| [ g.home_team_id, g.away_team_id ] }).order(:name)
  end
end
