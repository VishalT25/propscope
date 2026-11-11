# Loads history in the background (see Backfill::Run). Thin on purpose: all the work and the error handling live in the service.
class BackfillJob < ApplicationJob
  queue_as :default

  def perform(run_id) = Backfill::Run.call(BackfillRun.find(run_id))
end
