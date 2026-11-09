module Providers
  # The only code that knows vendor formats. Adapters return DTOs, never raw hashes.
  class Base
    CAPABILITIES = Set.new.freeze

    attr_reader :transport, :clock

    def initialize(transport:, clock: -> { Time.current })
      @transport = transport
      @clock = clock
    end

    def provider_key = raise(NotImplementedError)
    def capabilities = self.class::CAPABILITIES

    def fetch_teams(sport:)                         = raise(NotImplementedError)
    def fetch_players(sport:)                       = raise(NotImplementedError)
    def fetch_events(sport:, from:, to:)            = raise(NotImplementedError)
    def fetch_odds(sport:, event_ids: nil, from: nil, to: nil) = raise(NotImplementedError)
    def fetch_game_logs(sport:, date:)              = raise(NotImplementedError)
    def cost_of(request_kind, count = 1)            = raise(NotImplementedError)

    # Re-parse a stored raw payload (used by data:renormalize). Returns [kind, [DTOs]].
    def replay(_raw_payload) = raise(NotImplementedError)

    def live? = transport.metered?

    private

    # Every external call goes through here: budget guard, raw payload capture, then parse.
    def request(path, params = {}, cost: 1)
      body = if transport.metered?
        BudgetGuard.spend!(provider_key, cost) { transport.get(path, params) }
      else
        transport.get(path, params)
      end
      RawPayloadStore.capture(provider: provider_key, endpoint: path, params: params, status: 200, body: storage_body(body), fetched_at: clock.call)
      body
    end

    # What gets persisted in raw_payloads. Adapters may trim bulk the parser never reads.
    def storage_body(body) = body

    def parse_time(value) = value.present? ? Time.zone.parse(value.to_s)&.utc : nil
  end
end
