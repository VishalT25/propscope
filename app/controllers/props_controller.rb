class PropsController < PublicController
  before_action :load_filters

  def index
    @result = PropsQuery.call(filters: @filters, bookmaker_ids: enabled_bookmaker_ids)
    @games = PropsQuery.upcoming_games
  end

  # Live "Show N props" label for the filter drawer, as a Turbo Stream.
  def count
    total = PropsQuery.call(filters: @filters, bookmaker_ids: enabled_bookmaker_ids, paginate: false).total
    render turbo_stream: turbo_stream.update("apply_label", helpers.props_count_label(total))
  end

  private

  def load_filters = @filters = PropsQuery::Filters.from_params(params)
end
