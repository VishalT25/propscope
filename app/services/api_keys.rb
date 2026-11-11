# The keys for the data providers. An environment variable always wins (so .env installs and CI work as before); otherwise the key
# entered in Settings (stored encrypted, see Setting). The full key is never shown again: only where it came from and its last 4.
module ApiKeys
  class Missing < KeyError; end

  PROVIDERS = {
    "sports_game_odds" => { env: "SPORTSGAMEODDS_API_KEY", name: "SportsGameOdds", purpose: "odds and props" },
    "balldontlie" => { env: "BALLDONTLIE_API_KEY", name: "BallDontLie", purpose: "teams, players, schedule and box scores" }
  }.freeze

  class << self
    def get(provider) = ENV[meta(provider)[:env]].presence || Setting.get(setting_key(provider))

    def fetch(provider) = get(provider) || raise(Missing, "No #{meta(provider)[:name]} key yet. Add it in Settings, or set #{meta(provider)[:env]}.")

    def present?(provider) = get(provider).present?

    # :environment, :app, or nil when there is no key.
    def source(provider)
      return :environment if ENV[meta(provider)[:env]].present?

      :app if Setting.get(setting_key(provider)).present?
    end

    def set(provider, value) = Setting.set(setting_key(provider), value.to_s.strip)

    def clear(provider) = Setting.delete(setting_key(provider))

    # "••••1234": enough to recognise which key it is.
    def hint(provider)
      key = get(provider)
      key.present? ? "••••#{key.last(4)}" : nil
    end

    def name(provider) = meta(provider)[:name]

    def meta(provider) = PROVIDERS.fetch(provider.to_s)

    private

    def setting_key(provider) = "api_key.#{provider}"
  end
end
