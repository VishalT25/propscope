# Small key/value store for things a person sets from the app on their own install: API keys (encrypted), whether
# live data is on, their BallDontLie plan. Environment variables always win over these (see ApiKeys, LiveData).
class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :key, null: false
      t.text :value # encrypted (Rails attribute encryption), see Setting
      t.timestamps
    end
    add_index :settings, :key, unique: true
  end
end
