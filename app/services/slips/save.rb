module Slips
  # Saves the working slip (a PickSlip::Slip) as a snapshot. Only a fully priced slip can be saved: every leg needs a price at the
  # chosen book, otherwise there are no combined odds to remember. The working slip is left alone so it can be edited and saved again.
  class Save
    class Unpriced < StandardError; end

    def self.call(**) = new(**).call

    def initialize(user:, slip:, name: nil)
      @user = user
      @slip = slip
      @name = name.to_s.strip.presence
    end

    def call
      raise Unpriced, "Add a leg first." if @slip.nil? || @slip.legs.empty?
      raise Unpriced, "Every leg needs a current price at one book before you can save the slip." unless @slip.parlay

      ::Slip.transaction do
        record = @user.slips.create!(name: @name || default_name, bookmaker: @slip.book, stake: @slip.stake, decimal_odds: @slip.parlay.decimal)
        @slip.legs.each do |leg|
          record.legs.create!(market: leg.market, side: leg.pick.side, bookmaker: leg.chosen.bookmaker, line: leg.market.line,
                              american_odds: leg.chosen.american_odds, decimal_odds: leg.chosen.decimal_odds)
        end
        record
      end
    end

    private

    def default_name = "#{@slip.legs.size}-leg #{@slip.legs.size == 1 ? 'single' : 'parlay'}"
  end
end
