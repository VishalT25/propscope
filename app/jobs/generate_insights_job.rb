# Plain-English insights for upcoming props. Runs after hit rates.
class GenerateInsightsJob < ApplicationJob
  queue_as :default

  def perform = Insights::Engine.call
end
