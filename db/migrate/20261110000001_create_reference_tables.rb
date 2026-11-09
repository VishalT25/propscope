class CreateReferenceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :sports do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.timestamps
      t.index :key, unique: true
    end

    create_table :teams do |t|
      t.references :sport, null: false, foreign_key: true
      t.string :abbreviation, null: false
      t.string :name, null: false          # full name, e.g. "Boston Celtics"
      t.string :city
      t.string :conference
      t.string :division
      t.timestamps
      t.index %i[sport_id abbreviation], unique: true
    end

    create_table :players do |t|
      t.references :sport, null: false, foreign_key: true
      t.references :team, foreign_key: true   # current team; null for free agents
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :normalized_name, null: false  # see NameNormalizer
      t.string :position
      t.string :status, null: false, default: "active"
      t.timestamps
      t.index %i[sport_id normalized_name]
    end

    create_table :games do |t|
      t.references :sport, null: false, foreign_key: true
      t.references :home_team, null: false, foreign_key: { to_table: :teams }
      t.references :away_team, null: false, foreign_key: { to_table: :teams }
      t.datetime :starts_at, null: false                  # UTC
      t.date :slate_date, null: false                     # game's date in US Eastern
      t.integer :season, null: false                      # start year, e.g. 2026 for 2026-27
      t.string :status, null: false, default: "scheduled"
      t.integer :home_score
      t.integer :away_score
      t.timestamps
      t.index %i[sport_id home_team_id away_team_id slate_date], unique: true, name: "index_games_on_natural_key"
      t.index %i[sport_id slate_date]
      t.index :starts_at
    end

    create_table :external_ids do |t|
      t.string :provider, null: false
      t.string :external_type, null: false     # team | player | game
      t.string :external_id, null: false
      t.string :internal_type, null: false
      t.bigint :internal_id, null: false
      t.timestamps
      t.index %i[provider external_type external_id], unique: true, name: "index_external_ids_on_provider_type_and_id"
      t.index %i[internal_type internal_id]
    end

    create_table :unresolved_entities do |t|
      t.string :provider, null: false
      t.string :external_type, null: false
      t.string :external_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :reason, null: false
      t.datetime :resolved_at
      t.timestamps
      t.index %i[provider external_type external_id], unique: true, name: "index_unresolved_on_provider_type_and_id"
    end
  end
end
