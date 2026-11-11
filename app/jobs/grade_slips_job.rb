# Settles saved slip legs once their box scores are in. Chained after the nightly game-log ingest; safe to run any time.
class GradeSlipsJob < ApplicationJob
  queue_as :default

  def perform = Slips::Grade.call
end
