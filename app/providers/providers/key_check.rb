module Providers
  # One cheap call to find out whether a key works, so setup can say so before a long backfill. It goes through the budget guard like
  # any other call (SportsGameOdds bills per event, so the check costs one). For BallDontLie it also tries box scores, because the free
  # plan has none and hit rates are built from them.
  class KeyCheck
    Result = Data.define(:ok, :box_scores, :message) # box_scores is true/false for BallDontLie and nil for the others

    def self.call(provider, transport: nil) = new(provider, transport || Registry.live_transport(provider)).call

    def initialize(provider, transport)
      @provider = provider.to_s
      @transport = transport
    end

    def call
      public_send(:"check_#{@provider}")
    rescue ApiKeys::Missing
      failure("Paste a #{name} key first.")
    rescue BudgetGuard::BudgetExceeded
      failure("This month's #{name} budget is used up, so the key cannot be tested now.")
    rescue Faraday::UnauthorizedError, Faraday::ForbiddenError => e
      failure("#{name} did not accept that key (HTTP #{e.response_status}). Check you copied all of it.")
    rescue Faraday::TooManyRequestsError
      failure("#{name} says too many requests right now. Wait a minute and test again.")
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError
      failure("Could not reach #{name}. Check your internet connection and try again.")
    rescue Faraday::Error => e
      failure("#{name} answered with an error (HTTP #{e.response_status || 'unknown'}). Try again in a moment.")
    end

    def check_sports_game_odds
      spend { @transport.get("/events", "leagueID" => "NBA", "limit" => 1) }
      Result.new(true, nil, "Key works.")
    end

    def check_balldontlie
      spend { @transport.get("/teams") }
      begin
        spend { @transport.get("/stats", "dates[]" => (Date.current - 1).iso8601, "per_page" => 1) }
        Result.new(true, true, "Key works, and your plan includes box scores.")
      rescue Faraday::UnauthorizedError, Faraday::ForbiddenError
        Result.new(true, false, "Key works, but your plan has no box scores. Hit rates are built from them, so you need BallDontLie's paid (ALL-STAR) plan.")
      end
    end

    private

    def name = ApiKeys.name(@provider)

    def spend(&block) = BudgetGuard.spend!(@provider, 1, &block)

    def failure(message) = Result.new(false, nil, message)
  end
end
