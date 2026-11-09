module PropsHelper
  HIT_COLUMNS = [ [ "l5", "L5", "Last 5 games played" ], [ "l10", "L10", "Last 10 games played" ], [ "l20", "L20", "Last 20 games played" ],
                  [ "h2h", "H2H", "Against this opponent, this and last season" ], [ "season", "Season", "This season" ],
                  [ "prev_season", "Prev", "Last season" ] ].freeze

  TIER_STYLES = { "favorable" => "bg-hit/15 text-hit", "neutral" => "bg-surface-2 text-muted", "unfavorable" => "bg-miss/15 text-miss" }.freeze

  def pick_title(row) = "#{row.side.capitalize} #{number_with_precision(row.line, precision: 1)} #{row.stat.label}"

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

  def book_chip_codes
    books = enabled_book_keys ? all_bookmakers.select { |b| enabled_book_keys.include?(b.key) } : all_bookmakers
    [ books.first(2).map(&:code), [ books.size - 2, 0 ].max ]
  end
end
