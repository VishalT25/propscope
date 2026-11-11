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

  # Semantic colour for a hit-rate percentage (0-100). Small samples keep their colour (2 of 2 against an opponent is still
  # information); the game count is shown next to them instead (see small_sample?). Only "no games" is neutral.
  def hit_rate_tone(pct, _n = nil)
    return :muted if pct.nil?

    if pct >= HIT_GOOD then :hit
    elsif pct <= HIT_BAD then :miss
    else :push
    end
  end

  HIT_TONE_TEXT = { hit: "text-hit", miss: "text-miss", push: "text-push", muted: "text-muted" }.freeze

  def hit_rate_text_class(pct, n = nil) = HIT_TONE_TEXT.fetch(hit_rate_tone(pct, n))

  HIT_TONE_VAR = { hit: "--hit", miss: "--miss", push: "--push" }.freeze
  HIT_TINT_MAX = 42 # strongest background tint, in percent; keeps the number readable on top of it

  # Heat tint for table cells: stronger background for rates further from 50%. The number is set in the tone colour
  # mixed into the foreground (never the raw tone colour), so contrast holds at every tint strength and in both themes.
  def hit_rate_cell_style(pct, n = nil)
    tone = hit_rate_tone(pct, n)
    return "" if tone == :muted

    strength = ((pct - 50).abs * 1.1).clamp(8, HIT_TINT_MAX).round
    tint = pct >= 50 ? "--hit" : "--miss"
    "background-color: color-mix(in oklab, var(#{tint}) #{strength}%, transparent); " \
      "color: color-mix(in oklab, var(#{HIT_TONE_VAR.fetch(tone)}) 32%, var(--fg))"
  end

  # True when a rate rests on fewer than MIN_SAMPLE games (and at least one).
  def small_sample?(n) = n.to_i.positive? && n.to_i < MIN_SAMPLE

  # "n/a" only when there is nothing to show. Small samples still show the rate, coloured like any other
  # (see hit_rate_tone), with the game count beside it (see small_sample?).
  def percent_label(pct, _n = nil)
    return "n/a" if pct.nil?

    "#{pct.round}%"
  end

  DISPLAY_ZONE = "America/Toronto".freeze

  # Everything is stored in UTC; convert only here.
  def local_time(time) = time.in_time_zone(DISPLAY_ZONE).strftime("%-I:%M %p")
  def local_day(time) = time.in_time_zone(DISPLAY_ZONE).strftime("%a %b %-d")

  def updated_ago(time)
    return "not computed yet" unless time

    "updated #{time_ago_in_words(time)} ago"
  end

  def props_count_label(total) = "Show #{number_with_delimiter(total)} #{'prop'.pluralize(total)}"

  def league_nav_items
    [
      [ "Insights", league_insights_path(current_league) ],
      [ "Games", league_games_path(current_league) ],
      [ "Props", league_props_path(current_league) ],
      [ "EV+", league_ev_path(current_league) ],
      [ "Arbitrage", league_arbitrage_path(current_league) ]
    ]
  end

  # A nav link is active on its own page and below it (Props stays lit on a prop's detail page).
  def nav_active?(path) = request.path == path || request.path.start_with?("#{path}/")
end
