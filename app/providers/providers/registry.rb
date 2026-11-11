module Providers
  # Decides which adapter serves which capability, per environment (config/providers.yml).
  class Registry
    CONFIG = Rails.application.config_for(:providers)

    # What LIVE_DATA=true switches every capability to, whatever the environment (see docs/operations.md).
    FREE_BALLDONTLIE_INTERVAL = 12.5 # 5 requests a minute

    LIVE = { odds: "sports_game_odds", props: "sports_game_odds", reference: "balldontlie", stats: "balldontlie" }.freeze

    class << self
      def for(capability, env: Rails.env)
        source = LiveData.enabled? ? LIVE : CONFIG
        key = source.fetch(capability.to_sym) { raise ArgumentError, "unknown capability #{capability}" }
        build(key.to_s)
      end

      # Adapter used only for replay(raw): no network, parse times pinned to when the payload was fetched.
      def parser(provider, at:)
        klass = { "sports_game_odds" => SportsGameOdds, "balldontlie" => BallDontLie }.fetch(provider.to_s)
        klass.new(transport: NullTransport.new, clock: -> { at })
      end

      def budget_config(provider) = CONFIG.fetch(:budgets).fetch(provider.to_sym, {})

      # Seconds between calls. The free BallDontLie plan allows 5 requests a minute, the paid one 60; Settings records which one this is.
      def min_interval(provider)
        base = budget_config(provider)[:min_interval]
        provider.to_s == "balldontlie" && Setting.get("balldontlie_plan") == "free" ? [ base.to_f, FREE_BALLDONTLIE_INTERVAL ].max : base
      end

      private

      def build(key)
        case key
        when "fixture" then Fixture.new
        when "sports_game_odds"
          SportsGameOdds.new(transport: HttpTransport.new(
            provider: key, base_url: "https://api.sportsgameodds.com/v2/", min_interval: min_interval(key),
            auth: -> { { "X-Api-Key" => ApiKeys.fetch(key) } }
          ))
        when "balldontlie"
          BallDontLie.new(transport: HttpTransport.new(
            provider: key, base_url: "https://api.balldontlie.io/v1/", min_interval: min_interval(key),
            auth: -> { { "Authorization" => ApiKeys.fetch(key) } }
          ))
        else raise ArgumentError, "unknown provider #{key}"
        end
      end
    end
  end
end
