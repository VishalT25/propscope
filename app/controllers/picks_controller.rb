class PicksController < ApplicationController
  def create
    market = Market.where.not(player_id: nil).find(params[:market_id])
    side = %w[over under].include?(params[:side]) ? params[:side] : (return head(:unprocessable_content))
    price = BestPrice.for(market_ids: [ market.id ], bookmaker_ids: enabled_bookmaker_ids)[[ market.id, side ]]
    return redirect_back_or_to(root_path, alert: "No enabled book is offering that line right now.", status: :see_other) unless price

    pick = current_user.picks.find_or_initialize_by(market: market, side: side, bookmaker: price.bookmaker)
    pick.price_at_add ||= price.american_odds
    pick.save!
    redirect_back_or_to root_path, notice: "Added to your picks (#{price.bookmaker.name}).", status: :see_other
  end

  def destroy
    current_user.picks.find(params[:id]).destroy
    redirect_back_or_to root_path, status: :see_other
  end
end
