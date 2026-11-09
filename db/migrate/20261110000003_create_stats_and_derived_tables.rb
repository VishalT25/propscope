class CreateStatsAndDerivedTables < ActiveRecord::Migration[8.1]
  def change
    create_table :player_game_logs do |t|
      t.references :player, null: false, foreign_key: true
      t.references :game, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.references :opponent_team, null: false, foreign_key: { to_table: :teams }
      t.date :game_date, null: false
      t.integer :season, null: false
      t.boolean :home, null: false
      t.decimal :minutes, precision: 5, scale: 2, null: false, default: 0 # 0 means DNP
      t.integer :points, :rebounds, :assists, :threes_made, :steals, :blocks, :turnovers, :fouls, null: false, default: 0
      t.jsonb :stats, null: false, default: {}   # everything else the provider gave us
      t.timestamps
      t.index %i[player_id game_id], unique: true
      t.index %i[player_id game_date], order: { game_date: :desc }
      t.index %i[opponent_team_id season]
    end

    create_table :prop_hit_rates do |t|
      t.references :market, null: false, foreign_key: true
      t.string :side, null: false
      t.decimal :line, precision: 6, scale: 1
      t.decimal :l5, :l10, :l20, :h2h, :season, :prev_season, precision: 5, scale: 2 # percent 0-100
      t.integer :l5_n, :l10_n, :l20_n, :h2h_n, :season_n, :prev_season_n
      t.decimal :closing_line_hit_rate, precision: 5, scale: 2
      t.decimal :mean, :median, precision: 7, scale: 2
      t.datetime :computed_at, null: false
      t.timestamps
      t.index %i[market_id side], unique: true
    end

    create_table :defense_ranks do |t|
      t.references :team, null: false, foreign_key: true
      t.string :stat, null: false
      t.string :position, null: false
      t.decimal :avg_allowed, precision: 7, scale: 2, null: false
      t.integer :rank, null: false
      t.string :tier, null: false                # favorable | neutral | unfavorable
      t.integer :season, null: false
      t.datetime :computed_at, null: false
      t.timestamps
      t.index %i[team_id stat position season], unique: true, name: "index_defense_ranks_natural_key"
    end

    create_table :insights do |t|
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.references :game, foreign_key: true
      t.references :market, foreign_key: true
      t.string :side
      t.string :rule_key, null: false
      t.text :statement, null: false
      t.decimal :strength, precision: 6, scale: 2, null: false, default: 0
      t.datetime :computed_at, null: false
      t.timestamps
      t.index %i[game_id strength], order: { strength: :desc }
      t.index %i[subject_type subject_id]
    end
  end
end
