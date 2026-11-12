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

      # Seconds between calls: the pace the provider's plan allows (see config/providers.yml).
      def min_interval(provider) = budget_config(provider)[:min_interval]

      # A real HTTP transport for a provider, whatever LIVE_DATA says. Used to check a key; the key is read when a call is made.
      def live_transport(provider)
        key = provider.to_s
        base_url = { "sports_game_odds" => "https://api.sportsgameodds.com/v2/", "balldontlie" => "https://api.balldontlie.io/v1/" }.fetch(key)
        header = { "sports_game_odds" => "X-Api-Key", "balldontlie" => "Authorization" }.fetch(key)
        HttpTransport.new(provider: key, base_url: base_url, min_interval: min_interval(key), auth: -> { { header => ApiKeys.fetch(key) } })
      end

      private

      def build(key)
        case key
        when "fixture" then Fixture.new
        when "sports_game_odds" then SportsGameOdds.new(transport: live_transport(key))
        when "balldontlie" then BallDontLie.new(transport: live_transport(key))
        else raise ArgumentError, "unknown provider #{key}"
        end
      end
    end
  end
end
