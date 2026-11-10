class PicksController < ApplicationController
  # The slip body (frame "slip"): re-rendered when the viewer changes the book or the stake.
  def index
    cookies.permanent[:slip_book] = { value: params[:book].to_s, same_site: :lax } if params.key?(:book)
    cookies.permanent[:slip_stake] = { value: params[:stake].to_s, same_site: :lax } if params.key?(:stake)
    @slip = nil
    render partial: "picks/slip_frame", locals: { slip: slip }
  end

  def create
    market = Market.where.not(player_id: nil).find(params[:market_id])
    side = %w[over under].include?(params[:side]) ? params[:side] : (return head(:unprocessable_content))
    price = BestPrice.for(market_ids: [ market.id ], bookmaker_ids: enabled_bookmaker_ids)[[ market.id, side ]]
    return respond(alert: "No enabled book is offering that line right now.") unless price

    pick = current_user.picks.find_or_initialize_by(market: market, side: side)
    pick.bookmaker ||= price.bookmaker
    pick.price_at_add ||= price.american_odds
    pick.save!
    respond(market: market, side: side, picked: true, notice: "Added to your slip.")
  end

  def destroy
    pick = current_user.picks.find(params[:id])
    market, side = pick.market, pick.side
    pick.destroy
    respond(market: market, side: side, picked: false)
  end

  private

  # Turbo Stream: flip every "+" for this leg, update the slip count and the slip itself. No page reload.
  def respond(market: nil, side: nil, picked: nil, notice: nil, alert: nil)
    @slip = nil
    respond_to do |format|
      format.turbo_stream do
        streams = []
        streams << pick_button_stream(market, side, picked) if market
        streams << turbo_stream.update("picks_count", partial: "picks/count", locals: { count: current_user.picks.count })
        streams << turbo_stream.update("slip", partial: "picks/slip_body", locals: { slip: slip })
        streams << turbo_stream.update("toast", partial: "shared/toast", locals: { message: notice || alert, kind: alert ? :error : :ok }) if notice || alert
        render turbo_stream: streams
      end
      format.html { redirect_back_or_to root_path, notice: notice, alert: alert, status: :see_other }
    end
  end

  # Swap the + for every copy of this leg on the page (the table row and the mobile card both render one).
  def pick_button_stream(market, side, picked)
    html = render_to_string(partial: "props/pick_button", formats: [ :html ], locals: { market: market, side: side, picked: picked })
    turbo_stream.action_all(:update, "[data-pick='#{Integer(market.id)}-#{side}']", html)
  end
end
