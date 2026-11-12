module Slips
  # One link that opens FanDuel with these selections already in the bet slip:
  #   https://<region host>/addToBetslip?marketId[0]=…&selectionId[0]=…&marketId[1]=…&selectionId[1]=…
  # Checked by hand (desktop and mobile web, Ontario): this indexed form fills the slip with one leg or many; the plain form
  # (marketId=…&selectionId=…) is what SportsGameOdds supplies and only works on desktop.
  # The ids come from the price's own booking link and are the only thing taken from it: the address is built from the viewer's region,
  # never copied from a stored URL, and no partner or affiliate tag is added.
  class FanDuelLink
    Result = Data.define(:url, :used, :skipped)

    MARKET_ID = /\A\d+(\.\d+)?\z/
    SELECTION_ID = /\A\d+\z/

    def self.call(**) = new(**).call

    def initialize(region:, snapshots:)
      @region = region
      @snapshots = snapshots
    end

    def call
      pairs = @snapshots.map { |snapshot| [ snapshot, ids(snapshot) ] }
      used = pairs.select { |_, id| id }
      skipped = pairs.reject { |_, id| id }.map(&:first)
      Result.new(url: used.empty? ? nil : url_for(used.map(&:last)), used: used.map(&:first), skipped: skipped)
    end

    private

    # [market_id, selection_id] from the stored booking link, or nil when it is not a FanDuel selection link we can read.
    def ids(snapshot)
      return nil if snapshot.deeplink.blank?

      query = URI.decode_www_form(URI.parse(snapshot.deeplink).query.to_s).to_h
      market, selection = query.values_at("marketId", "selectionId")
      [ market, selection ] if market.to_s.match?(MARKET_ID) && selection.to_s.match?(SELECTION_ID)
    rescue URI::InvalidURIError
      nil
    end

    def url_for(id_pairs)
      "https://#{@region.fanduel_host}/addToBetslip?" + id_pairs.each_with_index.map { |(market, selection), i| "marketId[#{i}]=#{market}&selectionId[#{i}]=#{selection}" }.join("&")
    end
  end
end
