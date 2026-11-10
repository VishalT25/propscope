# Talks to the optional Python model service. It must never take the app down: short timeouts, and a circuit breaker
# that stops calling a service that keeps failing, so jobs skip it instantly instead of waiting on timeouts.
class ModelClient
  class Unavailable < StandardError; end

  FAILURE_THRESHOLD = 3
  OPEN_FOR = 5.minutes
  BATCH = 200

  def self.url = ENV["MODEL_SERVICE_URL"].presence
  def self.enabled? = url.present?

  def initialize(url: self.class.url, store: Rails.cache, clock: -> { Time.current })
    @url, @store, @clock = url, store, clock
    @conn = Faraday.new(url: url) do |f|
      f.request :json
      f.response :json
      f.response :raise_error
      f.options.open_timeout = 1
      f.options.timeout = 5
    end
  end

  def enabled? = @url.present?
  def open? = (until_time = @store.read(KEY_OPEN)) && until_time > @clock.call

  # rows: [{ id:, line:, features: {...} }] => { model_version:, predictions: [{ "id", "projection", "p_over", "p_under", ... }] }
  def predict(rows)
    raise Unavailable, "model service is not configured" unless enabled?
    raise Unavailable, "circuit open until #{@store.read(KEY_OPEN)}" if open?

    results = rows.each_slice(BATCH).map { |batch| @conn.post("/predict", { rows: batch }).body }
    @store.write(KEY_FAILURES, 0)
    { model_version: results.first&.dig("model_version"), predictions: results.flat_map { |r| r["predictions"] } }
  rescue Faraday::Error => e
    record_failure
    raise Unavailable, "#{e.class}: #{e.message}"
  end

  private

  KEY_FAILURES = "model_client/failures".freeze
  KEY_OPEN = "model_client/open_until".freeze

  def record_failure
    failures = @store.read(KEY_FAILURES).to_i + 1
    @store.write(KEY_FAILURES, failures)
    return if failures < FAILURE_THRESHOLD

    @store.write(KEY_OPEN, @clock.call + OPEN_FOR)
    @store.write(KEY_FAILURES, 0)
    Rails.logger.warn("[model] #{failures} failures in a row: pausing calls for #{OPEN_FOR.inspect}")
  end
end
