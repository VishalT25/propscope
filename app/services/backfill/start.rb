module Backfill
  # Starts loading history in the background. One run at a time: asking again while one is going returns it.
  class Start
    def self.call(seasons:)
      active = BackfillRun.active.order(:id).last
      return active if active

      run = BackfillRun.create!(seasons: seasons)
      BackfillJob.perform_later(run.id)
      run
    end
  end
end
