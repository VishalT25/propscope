# Saved slips: a snapshot of a parlay at the moment it was saved (book, stake, each leg's line and price), so the home page
# can show what you built and how it did, whatever the prices do afterwards.
class CreateSlips < ActiveRecord::Migration[8.1]
  def change
    create_table :slips do |t|
      t.references :user, null: false, foreign_key: true
      t.references :bookmaker, foreign_key: true # nil when each leg used its own best price
      t.string :name, null: false
      t.decimal :stake, precision: 12, scale: 2, null: false
      t.decimal :decimal_odds, precision: 14, scale: 4, null: false # combined price when saved
      t.timestamps
    end
    add_index :slips, %i[user_id created_at]

    create_table :slip_legs do |t|
      t.references :slip, null: false, foreign_key: true
      t.references :market, null: false, foreign_key: true
      t.references :bookmaker, null: false, foreign_key: true
      t.string :side, null: false
      t.decimal :line, precision: 7, scale: 2, null: false
      t.integer :american_odds, null: false
      t.decimal :decimal_odds, precision: 8, scale: 4, null: false
      t.string :result # hit, miss, push or void (DNP / postponed); nil until the box score is in
      t.decimal :actual, precision: 8, scale: 2 # the stat the player recorded
      t.datetime :graded_at
      t.timestamps
    end
    add_index :slip_legs, %i[slip_id market_id side], unique: true, name: "index_slip_legs_leg"
    add_index :slip_legs, :result
  end
end
