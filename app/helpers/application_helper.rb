module ApplicationHelper
  HIT_GOOD = 60
  HIT_BAD = 40
  MIN_SAMPLE = 5

  def app_name = Rails.configuration.x.app_name

  # Price in the viewer's chosen format. Prices are stored as integer American odds.
  def format_price(american, format: odds_format)
    return "–" if american.nil?

    if format == "decimal"
      OddsMath.american_to_decimal(american).round(2).to_s("F").then { |s| s.sub(/\.(\d)\z/, '.\10') }
    else
      american.positive? ? "+#{american}" : american.to_s
    end
  end

  # Semantic colour for a hit-rate percentage (0-100). Small samples stay neutral.
  def hit_rate_tone(pct, n = nil)
    return :muted if pct.nil? || (n && n < MIN_SAMPLE)

    if pct >= HIT_GOOD then :hit
    elsif pct <= HIT_BAD then :miss
    else :push
    end
  end

  HIT_TONE_TEXT = { hit: "text-hit", miss: "text-miss", push: "text-push", muted: "text-muted" }.freeze

  def hit_rate_text_class(pct, n = nil) = HIT_TONE_TEXT.fetch(hit_rate_tone(pct, n))

  # Heat tint for table cells: stronger background for rates further from 50%.
  def hit_rate_cell_style(pct, n = nil)
    tone = hit_rate_tone(pct, n)
    return "" if tone == :muted

    strength = ((pct - 50).abs * 1.1).clamp(8, 55).round
    color = pct >= 50 ? "var(--hit)" : "var(--miss)"
    "background-color: color-mix(in oklab, #{color} #{strength}%, transparent)"
  end

  def percent_label(pct, n = nil)
    return "n/a" if pct.nil? || (n && n < MIN_SAMPLE)

    "#{pct.round}%"
  end

  def league_nav_items
    [
      [ "Insights", league_insights_path(current_league), true ],
      [ "Games", league_games_path(current_league), true ],
      [ "Props", league_props_path(current_league), true ],
      [ "EV+", nil, false ],
      [ "Arbitrage", nil, false ]
    ]
  end
end
