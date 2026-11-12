module Slips
  # Where a slip can be sent to, and the link that does it. Only books whose links have been tested by hand are offered; today that is
  # FanDuel. DraftKings is left out on purpose: the links we get for it fail (single leg or several), so offering them would be worse than
  # offering nothing. See docs/providers/sportsbook_links.md.
  class Handoff
    Target = Data.define(:bookmaker, :url, :included, :total, :missing, :american)

    VERIFIED = { "fanduel" => FanDuelLink }.freeze

    def self.call(**) = new(**).call

    # A link for one leg's price, or nil when its book is not one we can send to.
    def self.leg_url(snapshot, region:)
      builder = VERIFIED[snapshot.bookmaker.key] or return nil

      builder.call(region: region, snapshots: [ snapshot ]).url
    end

    def initialize(slip:, region:)
      @slip = slip
      @region = region
    end

    def call
      return [] if @slip.nil? || @slip.legs.empty?

      VERIFIED.filter_map { |key, builder| target(key, builder) }
    end

    private

    def target(key, builder)
      option = @slip.options.find { |o| o.bookmaker.key == key } or return nil
      offered = @slip.legs.map { |leg| [ leg, leg.offers[option.bookmaker.id] ] }
      result = builder.call(region: @region, snapshots: offered.filter_map(&:last))
      return nil unless result.url

      linked = result.used.to_set(&:id)
      missing = offered.reject { |_, snapshot| snapshot && linked.include?(snapshot.id) }.map(&:first)
      Target.new(bookmaker: option.bookmaker, url: result.url, included: result.used.size, total: @slip.legs.size, missing: missing, american: option.american)
    end
  end
end
