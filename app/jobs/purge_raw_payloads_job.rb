# Raw payloads are kept 14 days (just enough to re-normalize after a parser fix).
class PurgeRawPayloadsJob < ApplicationJob
  queue_as :default

  def perform = RawPayload.expired.in_batches.delete_all
end
