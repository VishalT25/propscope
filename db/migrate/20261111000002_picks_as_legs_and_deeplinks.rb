class PicksAsLegsAndDeeplinks < ActiveRecord::Migration[8.1]
  def change
    # A pick is now one LEG (market + side) of the slip. The book is chosen on the slip, not when adding.
    remove_index :picks, name: "index_picks_natural_key"
    add_index :picks, %i[user_id market_id side], unique: true, name: "index_picks_leg"
    # The book's own betslip link for this selection, when the provider supplies one.
    add_column :odds_snapshots, :deeplink, :text
  end
end
