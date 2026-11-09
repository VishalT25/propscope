class CreateOddsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :bookmakers do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :code, null: false                 # short text badge, e.g. "DK"
      t.string :kind, null: false, default: "sportsbook" # sportsbook | dfs | exchange | prediction
      t.boolean :sharp, null: false, default: false
      t.timestamps
      t.index :key, unique: true
    end

    create_table :markets do |t|
      t.references :game, null: false, foreign_key: true
      t.references :player, foreign_key: true     # null for game-level markets
      t.string :market_type, null: false          # moneyline, spread, total, player_points, ...
      t.string :period, null: false, default: "game"
      t.decimal :line, precision: 6, scale: 1     # null for moneyline
      t.boolean :is_alternate, null: false, default: false
      t.timestamps
      t.index %i[game_id player_id market_type period line is_alternate],
              unique: true, nulls_not_distinct: true, name: "index_markets_on_natural_key"
    end

    create_table :odds_snapshots do |t|
      t.references :market, null: false, foreign_key: true
      t.references :bookmaker, null: false, foreign_key: true
      t.string :outcome, null: false              # over | under | home | away
      t.integer :american_odds, null: false
      t.decimal :decimal_odds, precision: 8, scale: 4, null: false
      t.decimal :line, precision: 6, scale: 1
      t.datetime :captured_at, null: false
      t.string :source_provider, null: false
      t.boolean :is_closing, null: false, default: false
      t.timestamps
      t.index %i[market_id outcome bookmaker_id captured_at], order: { captured_at: :desc }, name: "index_odds_snapshots_latest"
      t.index %i[market_id is_closing]
    end
  end
end
