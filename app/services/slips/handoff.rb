module Slips
  # Where a slip can be sent to, and the link that does it. Only books whose links have been tested by hand are offered; today that is
  # FanDuel. DraftKings is left out on purpose: the links we get for it fail (single leg or several), so offering them would be worse than
  # offering nothing. See docs/providers/sportsbook_links.md.
  #
  # Works for the slip being built (a PickSlip::Slip) and for a saved one (a ::Slip): either way each leg is paired with the book's
  # current price for it. A target comes back even when no leg can be linked (url nil), so the page can say why instead of saying nothing.
  class Handoff
    # Why a leg is not in the link: :started (its game has begun), :not_offered (the book has no price for it), :alternate (an alternate
    # line: SportsGameOdds gives no link for those) or :no_link (a price with no usable link).
    Skip = Data.define(:name, :market_id, :reason)
    Target = Data.define(:bookmaker, :url, :included, :total, :skipped, :american)
    Entry = Data.define(:name, :market, :game, :snapshot) # one leg, and the book's current price for it (nil when it has none)

    VERIFIED = { "fanduel" => FanDuelLink }.freeze

    # A slip being built.
    def self.call(slip:, region:, now: Time.current)
      return [] if slip.nil? || slip.legs.empty?

      VERIFIED.filter_map do |key, builder|
        option = slip.options.find { |o| o.bookmaker.key == key } or next
        entries = slip.legs.map { |leg| Entry.new(name: leg.player.full_name, market: leg.market, game: leg.game, snapshot: leg.offers[option.bookmaker.id]) }
        target(option.bookmaker, builder, entries, region, now, option.american)
      end
    end

    # A saved slip: the legs are looked up at the book as it is now (the link only adds the selections, the book shows its own price).
    def self.for_saved(slip:, region:, now: Time.current)
      return [] if slip.legs.empty?

      books = Bookmaker.where(key: VERIFIED.keys).index_by(&:key)
      VERIFIED.filter_map do |key, builder|
        book = books[key] or next
        prices = latest_prices(book, slip.legs)
        entries = slip.legs.map { |leg| Entry.new(name: leg.market.player.full_name, market: leg.market, game: leg.market.game, snapshot: prices[[ leg.market_id, leg.side ]]) }
        target(book, builder, entries, region, now, nil)
      end
    end

    # A link for one leg's price, or nil when its book is not one we can send to.
    def self.leg_url(snapshot, region:)
      builder = VERIFIED[snapshot.bookmaker.key] or return nil

      builder.call(region: region, snapshots: [ snapshot ]).url
    end

    def self.latest_prices(book, legs)
      OddsSnapshot.where(bookmaker: book, market_id: legs.map(&:market_id), outcome: legs.map(&:side)).order(captured_at: :desc)
                  .each_with_object({}) { |s, prices| prices[[ s.market_id, s.outcome ]] ||= s }
    end
    private_class_method :latest_prices

    def self.target(book, builder, entries, region, now, american)
      result = builder.call(region: region, snapshots: entries.reject { |e| started?(e, now) }.filter_map(&:snapshot))
      linked = result.used.to_set(&:id)
      skipped = entries.filter_map { |e| (reason = reason_skipped(e, linked, now)) && Skip.new(e.name, e.market.id, reason) }
      return nil if result.url.nil? && skipped.all? { |s| s.reason == :started } # nothing to send and nothing to explain

      Target.new(bookmaker: book, url: result.url, included: result.used.size, total: entries.size, skipped: skipped, american: american)
    end
    private_class_method :target

    def self.started?(entry, now) = entry.game.starts_at <= now
    private_class_method :started?

    def self.reason_skipped(entry, linked, now)
      if started?(entry, now) then :started
      elsif entry.snapshot.nil? then :not_offered
      elsif !linked.include?(entry.snapshot.id) then entry.market.is_alternate ? :alternate : :no_link
      end
    end
    private_class_method :reason_skipped
  end
end
