# prop_hit_rates for every upcoming player prop. Runs after each odds snapshot and nightly after stats.
class PrecomputeHitRatesJob < ApplicationJob
  queue_as :default

  def perform
    HitRates::Precompute.call
    GenerateInsightsJob.perform_later
  end
end
