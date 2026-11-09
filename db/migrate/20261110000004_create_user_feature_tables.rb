class CreateUserFeatureTables < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_filters do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :scope, null: false, default: "props"  # props | ev
      t.jsonb :params, null: false, default: {}
      t.timestamps
    end

    create_table :picks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :market, null: false, foreign_key: true
      t.string :side, null: false
      t.references :bookmaker, null: false, foreign_key: true
      t.integer :price_at_add, null: false         # American odds when added
      t.timestamps
      t.index %i[user_id market_id side bookmaker_id], unique: true, name: "index_picks_natural_key"
    end
  end
end
