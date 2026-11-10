class CreatePredictions < ActiveRecord::Migration[8.1]
  def change
    create_table :predictions do |t|
      t.references :market, null: false, foreign_key: true
      t.string :side, null: false                       # over | under
      t.decimal :probability, precision: 6, scale: 5, null: false  # chance this side wins, pushes excluded
      t.decimal :projection, precision: 6, scale: 2     # the model's expected stat value
      t.string :model_version, null: false
      t.datetime :computed_at, null: false
      t.timestamps
      t.index %i[market_id side], unique: true
    end
  end
end
