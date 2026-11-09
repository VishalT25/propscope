# Builds the JSON config the Stimulus chart controller renders. Colour names are design tokens, not hex values.
module ChartsHelper
  OUTCOME_COLOR = ->(outcome) { outcome.nil? ? "push" : (outcome ? "hit" : "miss") }

  def bars_chart_config(detail)
    bars = detail.bars
    {
      type: "bar", decimals: 0, labels: bars.map { |b| "#{b.date.strftime('%-m/%-d')} #{b.label}" },
      datasets: [
        { kind: "bars", label: detail.market.market_type.then { StatCatalog.for_market(_1).label }, data: bars.map { |b| b.value.to_f }, colors: bars.map { |b| OUTCOME_COLOR.call(b.outcome) } },
        { kind: "line", label: "Line #{number_with_precision(detail.market.line, precision: 1)}", data: bars.map { detail.market.line.to_f }, color: "fg", dash: true },
        { kind: "closing", label: "Closing line", data: bars.map { |b| b.closing_line&.to_f }, color: "ev", step: true, hidden: true }
      ]
    }
  end

  def support_chart_config(series)
    bars = series.bars
    {
      type: "bar", decimals: 1, labels: bars.map { |b| "#{b.date.strftime('%-m/%-d')} #{b.label}" },
      datasets: [
        { kind: "bars", label: series.label, data: bars.map { |b| b.value.to_f }, colors: bars.map { "muted" } },
        { kind: "avg", group: "mean", label: "Average", data: bars.map { series.mean&.to_f }, color: "accent", dash: true },
        { kind: "avg", group: "median", label: "Median", data: bars.map { series.median&.to_f }, color: "accent-2", dash: true, hidden: true }
      ]
    }
  end

  def movement_chart_config(movement)
    points = movement.points
    {
      type: "line", decimals: 1, beginAtZero: false, labels: points.map { |p| "#{local_day(p.at)} #{local_time(p.at)}" },
      datasets: [ { kind: "movement", label: "Consensus line", data: points.map { |p| p.line.to_f }, color: "accent", step: true } ]
    }
  end

  def change_arrow(change)
    case change
    when 1 then tag.span("▲", class: "text-hit", title: "Went up")
    when -1 then tag.span("▼", class: "text-miss", title: "Went down")
    else tag.span("–", class: "text-muted")
    end
  end
end
