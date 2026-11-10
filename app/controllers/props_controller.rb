class PropsController < PublicController
  before_action :load_filters, only: %i[index count]

  def index
    @result = PropsQuery.call(filters: @filters, bookmaker_ids: enabled_bookmaker_ids)
    @games = PropsQuery.upcoming_games
  end

  # Live "Show N props" label for the filter drawer, as a Turbo Stream.
  def count
    total = PropsQuery.call(filters: @filters, bookmaker_ids: enabled_bookmaker_ids, paginate: false).total
    render turbo_stream: turbo_stream.update("apply_label", helpers.props_count_label(total))
  end

  def show
    market = Market.where.not(player_id: nil).where(market_type: StatCatalog::BY_MARKET.keys).includes(:game, player: :team).find(params[:market_id])
    @detail = PropDetail.call(market: market, side: params[:side], window: params[:window], support: params[:support], position: params[:pos],
                              dpos: params[:dpos], all: params[:all] == "1", move: params[:move], bookmaker_ids: enabled_bookmaker_ids)
  end

  private

  def load_filters = @filters = PropsQuery::Filters.from_params(params)
end
