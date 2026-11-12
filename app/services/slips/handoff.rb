module Slips
  # Where a slip can be sent to, and the link that does it. Only books whose links have been tested by hand are offered; today that is
  # FanDuel. DraftKings is left out on purpose: the links we get for it fail (single leg or several), so offering them would be worse than
  # offering nothing. See docs/providers/sportsbook_links.md.
  class Handoff
    # skipped: [[leg, reason]] for every leg that is not in the link. Reasons: :started (its game has begun), :not_offered (the book has no
    # price for it), :alternate (an alternate line: SportsGameOdds gives no link for those) or :no_link (a price with no usable link).
    Target = Data.define(:bookmaker, :url, :included, :total, :skipped, :american)

    VERIFIED = { "fanduel" => FanDuelLink }.freeze

    def self.call(**) = new(**).call

    # A link for one leg's price, or nil when its book is not one we can send to.
    def self.leg_url(snapshot, region:)
      builder = VERIFIED[snapshot.bookmaker.key] or return nil

      builder.call(region: region, snapshots: [ snapshot ]).url
    end

    def initialize(slip:, region:, now: Time.current)
      @slip = slip
      @region = region
      @now = now
    end

    def call
      return [] if @slip.nil? || @slip.legs.empty?

      VERIFIED.filter_map { |key, builder| target(key, builder) }
    end

    private

    def target(key, builder)
      option = @slip.options.find { |o| o.bookmaker.key == key } or return nil
      offered = @slip.legs.map { |leg| [ leg, leg.offers[option.bookmaker.id] ] }
      open = offered.reject { |leg, _| started?(leg) }
      result = builder.call(region: @region, snapshots: open.filter_map(&:last))
      return nil unless result.url

      linked = result.used.to_set(&:id)
      skipped = offered.filter_map { |leg, snapshot| (reason = reason_skipped(leg, snapshot, linked)) && [ leg, reason ] }
      Target.new(bookmaker: option.bookmaker, url: result.url, included: result.used.size, total: @slip.legs.size, skipped: skipped, american: option.american)
    end

    def started?(leg) = leg.game.starts_at <= @now

    def reason_skipped(leg, snapshot, linked)
      if started?(leg) then :started
      elsif snapshot.nil? then :not_offered
      elsif !linked.include?(snapshot.id) then leg.market.is_alternate ? :alternate : :no_link
      end
    end
  end
end
