module Dto
  # One bookmaker price for one side of one market. Carries enough about the event to resolve the game.
  OddsQuote = Data.define(
    :provider, :event_id, :home_team, :away_team, :starts_at,
    :bookmaker_key, :market_type, :period, :player, :line, :outcome, :american_odds, :captured_at, :is_alternate, :deeplink
  ) do
    def initialize(deeplink: nil, **rest) = super
  end
end
