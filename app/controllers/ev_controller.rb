class EvController < PublicController
  def index
    @filters = Ev::Opportunities::Filters.from_params(params)
    @result = Ev::Opportunities.call(filters: @filters, bookmaker_ids: enabled_bookmaker_ids)
    @books = Bookmaker.all.index_by(&:id)
  end
end
