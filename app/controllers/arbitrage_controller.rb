class ArbitrageController < PublicController
  def index
    @min_profit = BigDecimal((BigDecimal(params[:min_profit].to_s, exception: false) || 0).clamp(0, 100).to_s)
    @stake = BigDecimal((BigDecimal(params[:stake].to_s, exception: false) || 100).clamp(1, 100_000).to_s) # clamp can return the Integer bound
    @rows = ArbitrageFinder.call(min_profit: @min_profit, bookmaker_ids: enabled_bookmaker_ids)
    @books = Bookmaker.all.index_by(&:id)
  end
end
