require "faraday/retry"

module Providers
  # Real HTTP with retries on 429/5xx and a per-provider minimum interval between calls.
  class HttpTransport
    @last_call = {}
    class << self
      attr_reader :last_call
    end

    def initialize(provider:, base_url:, auth:, min_interval: 0)
      @provider = provider
      @min_interval = min_interval.to_f
      @auth = auth
      @conn = Faraday.new(url: base_url) do |f|
        # Order matters: raise_error must wrap retry so retry sees raw 429/5xx responses before they raise.
        f.response :raise_error
        f.request :retry, max: 4, interval: 1.0, backoff_factor: 2, retry_statuses: [ 429, 500, 502, 503, 504 ],
                          methods: %i[get], exceptions: [ Faraday::RetriableResponse, Faraday::TimeoutError, Faraday::ConnectionFailed ]
        f.response :json
        f.options.timeout = 30
      end
    end

    def metered? = true

    def get(path, params = {})
      throttle
      @conn.get(path.delete_prefix("/"), params, @auth.call).body
    end

    private

    def throttle
      last = self.class.last_call[@provider]
      wait = last ? @min_interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - last) : 0
      sleep(wait) if wait.positive?
      self.class.last_call[@provider] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
