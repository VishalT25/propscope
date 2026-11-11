# What the setup page needs to say how long a load will take: how many provider requests it has made, and when the current step began.
class AddProgressToBackfillRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :backfill_runs, :requests_done, :integer, default: 0, null: false
    add_column :backfill_runs, :phase_requests_start, :integer, default: 0, null: false # requests_done when the current step began
    add_column :backfill_runs, :phase_started_at, :datetime
  end
end
