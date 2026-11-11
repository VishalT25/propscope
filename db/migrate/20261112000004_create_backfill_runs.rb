# One row per attempt to load history from the live providers, so the setup page can show progress and a failed or interrupted
# run can be resumed (days that already have box scores are skipped).
class CreateBackfillRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :backfill_runs do |t|
      t.string :state, null: false, default: "queued" # queued running paused failed done cancelled
      t.string :phase                                  # reference box_scores ranks odds
      t.integer :seasons, null: false, default: 2
      t.integer :total_days, default: 0, null: false
      t.integer :done_days, default: 0, null: false
      t.text :message                                  # what to tell the user (why it paused or failed)
      t.boolean :cancel_requested, default: false, null: false
      t.datetime :started_at
      t.datetime :heartbeat_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :backfill_runs, :state
  end
end
