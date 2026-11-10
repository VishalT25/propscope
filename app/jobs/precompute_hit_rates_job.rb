# prop_hit_rates for every upcoming player prop. Runs after each odds snapshot and nightly after stats.
class PrecomputeHitRatesJob < ApplicationJob
  queue_as :default

  def perform
    HitRates::Precompute.call
    GenerateInsightsJob.perform_later
    PredictPropsJob.perform_later # no-op unless MODEL_SERVICE_URL is set
  end
end
