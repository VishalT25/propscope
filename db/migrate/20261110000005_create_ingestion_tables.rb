class CreateIngestionTables < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_payloads do |t|
      t.string :provider, null: false
      t.string :endpoint, null: false
      t.string :params_digest, null: false
      t.datetime :fetched_at, null: false
      t.integer :status, null: false
      t.jsonb :body, null: false
      t.string :body_sha256, null: false
      t.timestamps
      t.index %i[provider fetched_at]
      t.index %i[provider endpoint params_digest]
    end

    create_table :api_usages do |t|
      t.string :provider, null: false
      t.string :period, null: false              # YYYY-MM
      t.bigint :units_used, null: false, default: 0
      t.bigint :units_limit                       # null = no monthly cap (rate-limited only)
      t.timestamps
      t.index %i[provider period], unique: true
    end
  end
end
