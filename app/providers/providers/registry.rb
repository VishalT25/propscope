module Providers
  # Decides which adapter serves which capability, per environment (config/providers.yml).
  class Registry
    CONFIG = Rails.application.config_for(:providers)

    # What LIVE_DATA=true switches every capability to, whatever the environment (see docs/operations.md).
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

      private

      def build(key)
        case key
        when "fixture" then Fixture.new
        when "sports_game_odds"
          SportsGameOdds.new(transport: HttpTransport.new(
            provider: key, base_url: "https://api.sportsgameodds.com/v2/", min_interval: budget_config(key)[:min_interval],
            auth: -> { { "X-Api-Key" => ENV.fetch("SPORTSGAMEODDS_API_KEY") } }
          ))
        when "balldontlie"
          BallDontLie.new(transport: HttpTransport.new(
            provider: key, base_url: "https://api.balldontlie.io/v1/", min_interval: budget_config(key)[:min_interval],
            auth: -> { { "Authorization" => ENV.fetch("BALLDONTLIE_API_KEY") } }
          ))
        else raise ArgumentError, "unknown provider #{key}"
        end
      end
    end
  end
end
