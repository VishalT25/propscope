# Where the person bets. Sportsbooks are licensed per province and per state, and their site addresses (and which of them exist at
# all) differ by place, so links that open a slip at a sportsbook have to know. See Region.
class AddRegionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :region, :string, default: "us", null: false
  end
end
