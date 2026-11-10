module PropsHelper
  HIT_COLUMNS = [ [ "l5", "L5", "Last 5 games played" ], [ "l10", "L10", "Last 10 games played" ], [ "l20", "L20", "Last 20 games played" ],
                  [ "h2h", "H2H", "Against this opponent, this and last season" ], [ "season", "Season", "This season" ],
                  [ "prev_season", "Prev", "Last season" ] ].freeze

  TIER_STYLES = { "favorable" => "bg-hit/15 text-hit", "neutral" => "bg-surface-2 text-muted", "unfavorable" => "bg-miss/15 text-miss" }.freeze

  def pick_label(side, line, stat) = "#{side.capitalize} #{number_with_precision(line, precision: 1)} #{stat.label}"
  def pick_title(row) = pick_label(row.side, row.line, row.stat)
  def detail_pick_title(detail) = pick_label(detail.side, detail.market.line, StatCatalog.for_market(detail.market.market_type))

  def model_pct(prediction) = prediction && (prediction.probability * 100)

  def model_tooltip(row)
    p = row.prediction
    "Model (#{p.model_version}) projects #{number_with_precision(p.projection, precision: 1)} #{row.stat.short}: #{number_with_precision(p.probability * 100, precision: 0)}% chance of the #{row.side}, pushes excluded. A projection from past form, not a guarantee."
  end

  def hits_in(rate, n) = rate && n ? (rate * n / 100).round : nil

  def hit_tooltip(label, rate, n)
    return "#{label}: no games" if n.to_i.zero?
    return "#{label}: #{hits_in(rate, n)} of #{n} (small sample)" if n < ApplicationHelper::MIN_SAMPLE

    "#{label}: hit #{hits_in(rate, n)} of #{n} games"
  end

  def tier_tooltip(row)
    return "No defence data yet" unless row.opp_rank

    "#{row.opponent.abbreviation} allow #{row.opp_rank.avg_allowed} #{row.stat.short} per game to #{row.opp_rank.position} players " \
      "(rank #{row.opp_rank.rank}; 1 = toughest defence). #{row.tier.capitalize} for this #{row.side}."
  end

  # Next sort direction when clicking a column: toggle if already sorted, else the column's natural default.
  def sort_link_params(filters, key)
    dir = filters.sort == key ? (filters.dir == "desc" ? "asc" : "desc") : (%w[opp_rank].include?(key) ? "asc" : "desc")
    filters.to_query(sort: key, dir: dir, page: nil)
  end

  def sort_arrow(filters, key)
    return "" unless filters.sort == key

    filters.dir == "desc" ? " ↓" : " ↑"
  end

  # Re-posts the applied filters (not the live draft) when saving a template.
  def hidden_filter_fields(filters)
    safe_join(filters.to_query.except(:sort, :dir).flat_map do |key, value|
      Array(value).map { |v| hidden_field_tag(Array(value).size > 1 || value.is_a?(Array) ? "#{key}[]" : key, v, id: nil) }
    end)
  end

  def book_chip_books
    books = enabled_book_keys ? all_bookmakers.select { |b| enabled_book_keys.include?(b.key) } : all_bookmakers
    [ books.first(2), [ books.size - 2, 0 ].max ]
  end

  # Link to the detail page keeping the window / supporting stat / position tab the viewer picked.
  def detail_path(detail, **overrides)
    keep = { window: params[:window], support: params[:support], pos: params[:pos], dpos: params[:dpos], move: params[:move], all: params[:all] }.compact_blank
    league_prop_path(current_league, detail.market, overrides.delete(:side) || detail.side, **keep.merge(overrides).compact_blank)
  end

  # Pill text: season windows read as years (2026 / 2025) like the reference product.
  def window_pill_label(key, season)
    case key
    when "season" then season.to_s
    when "prev_season" then (season - 1).to_s
    else window_label(key)
    end
  end

  def streak_statement(detail)
    s = detail.streak
    stat = StatCatalog.for_market(detail.market.market_type)
    "#{detail.player.full_name} has exceeded #{number_with_precision(detail.market.line, precision: 1)} #{stat.label.downcase} in #{s.count} straight games " \
      "(#{number_with_precision(s.average, precision: 1)} average)."
  end

  def window_label(key) = HIT_COLUMNS.find { |k, _, _| k == key }&.second || key.upcase

  def picks_path_for(pick) = pick_path(pick)

  # Which legs are on the slip, loaded once per request instead of once per row.
  def picked_leg?(market, side)
    @picked_legs ||= current_user ? current_user.picks.pluck(:market_id, :side).to_set : Set.new
    @picked_legs.include?([ market.id, side ])
  end

  # Plain-text slip for sharing or pasting next to a book's betslip.
  def slip_text(slip)
    return "" if slip.nil? || slip.legs.empty?

    lines = slip.legs.map do |l|
      price = l.chosen ? "#{format_price(l.chosen.american_odds)} #{l.chosen.bookmaker.code}" : "not offered"
      "- #{l.player.full_name} #{l.pick.side} #{number_with_precision(l.market.line, precision: 1)} #{l.stat.short} (#{price})"
    end
    header = slip.book ? "Slip at #{slip.book.name}" : "Slip (best price per leg)"
    footer = slip.parlay ? "#{slip.parlay.legs == 1 ? 'Single' : "#{slip.parlay.legs}-leg parlay"}: #{format_price(slip.parlay.american)} | #{number_to_currency(slip.parlay.stake)} pays #{number_to_currency(slip.parlay.payout)}" : "No combined odds (some legs not offered)"
    ([ header ] + lines + [ footer ]).join("\n")
  end
end
