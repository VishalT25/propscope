module SlipsHelper
  SLIP_STATUS = {
    won: [ "Won", "text-hit" ],
    lost: [ "Lost", "text-miss" ],
    push: [ "Push", "text-push" ],
    pending: [ "In play", "text-muted" ]
  }.freeze

  LEG_RESULT = {
    "hit" => [ "Hit", "text-hit" ],
    "miss" => [ "Miss", "text-miss" ],
    "push" => [ "Push", "text-push" ],
    "void" => [ "Void", "text-muted" ]
  }.freeze

  def slip_status_label(settlement) = SLIP_STATUS.fetch(settlement.status)

  # [label, css class, detail] for one saved leg. The detail is the recorded stat, or when it tips off while pending.
  def slip_leg_result(leg)
    if leg.result
      label, css = LEG_RESULT.fetch(leg.result)
      detail = leg.result == "void" ? "did not play" : number_with_precision(leg.actual, precision: 0)
      [ label, css, detail ]
    else
      game = leg.market.game
      [ "Pending", "text-muted", game.starts_at > Time.current ? "#{local_day(game.starts_at)}, #{local_time(game.starts_at)}" : "awaiting box score" ]
    end
  end

  def slip_leg_label(leg)
    "#{leg.side.capitalize} #{number_with_precision(leg.line, precision: 1)} #{StatCatalog.for_market(leg.market.market_type).short}"
  end
end
