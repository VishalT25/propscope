class AddEnabledBookmakersToUsers < ActiveRecord::Migration[8.1]
  def change
    # null = every book counts toward "best price"; otherwise the keys the user enabled.
    add_column :users, :enabled_bookmaker_keys, :jsonb
  end
end
