# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_10_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_usages", force: :cascade do |t|
    t.string "provider", null: false
    t.string "period", null: false
    t.bigint "units_used", default: 0, null: false
    t.bigint "units_limit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "period"], name: "index_api_usages_on_provider_and_period", unique: true
  end

  create_table "bookmakers", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.string "code", null: false
    t.string "kind", default: "sportsbook", null: false
    t.boolean "sharp", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_bookmakers_on_key", unique: true
  end

  create_table "defense_ranks", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.string "stat", null: false
    t.string "position", null: false
    t.decimal "avg_allowed", precision: 7, scale: 2, null: false
    t.integer "rank", null: false
    t.string "tier", null: false
    t.integer "season", null: false
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "stat", "position", "season"], name: "index_defense_ranks_natural_key", unique: true
    t.index ["team_id"], name: "index_defense_ranks_on_team_id"
  end

  create_table "external_ids", force: :cascade do |t|
    t.string "provider", null: false
    t.string "external_type", null: false
    t.string "external_id", null: false
    t.string "internal_type", null: false
    t.bigint "internal_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["internal_type", "internal_id"], name: "index_external_ids_on_internal_type_and_internal_id"
    t.index ["provider", "external_type", "external_id"], name: "index_external_ids_on_provider_type_and_id", unique: true
  end

  create_table "games", force: :cascade do |t|
    t.bigint "sport_id", null: false
    t.bigint "home_team_id", null: false
    t.bigint "away_team_id", null: false
    t.datetime "starts_at", null: false
    t.date "slate_date", null: false
    t.integer "season", null: false
    t.string "status", default: "scheduled", null: false
    t.integer "home_score"
    t.integer "away_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["away_team_id"], name: "index_games_on_away_team_id"
    t.index ["home_team_id"], name: "index_games_on_home_team_id"
    t.index ["sport_id", "home_team_id", "away_team_id", "slate_date"], name: "index_games_on_natural_key", unique: true
    t.index ["sport_id", "slate_date"], name: "index_games_on_sport_id_and_slate_date"
    t.index ["sport_id"], name: "index_games_on_sport_id"
    t.index ["starts_at"], name: "index_games_on_starts_at"
  end

  create_table "insights", force: :cascade do |t|
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.bigint "game_id"
    t.bigint "market_id"
    t.string "side"
    t.string "rule_key", null: false
    t.text "statement", null: false
    t.decimal "strength", precision: 6, scale: 2, default: "0.0", null: false
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "strength"], name: "index_insights_on_game_id_and_strength", order: { strength: :desc }
    t.index ["game_id"], name: "index_insights_on_game_id"
    t.index ["market_id"], name: "index_insights_on_market_id"
    t.index ["subject_type", "subject_id"], name: "index_insights_on_subject_type_and_subject_id"
  end

  create_table "markets", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "player_id"
    t.string "market_type", null: false
    t.string "period", default: "game", null: false
    t.decimal "line", precision: 6, scale: 1
    t.boolean "is_alternate", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "player_id", "market_type", "period", "line", "is_alternate"], name: "index_markets_on_natural_key", unique: true, nulls_not_distinct: true
    t.index ["game_id"], name: "index_markets_on_game_id"
    t.index ["player_id"], name: "index_markets_on_player_id"
  end

  create_table "odds_snapshots", force: :cascade do |t|
    t.bigint "market_id", null: false
    t.bigint "bookmaker_id", null: false
    t.string "outcome", null: false
    t.integer "american_odds", null: false
    t.decimal "decimal_odds", precision: 8, scale: 4, null: false
    t.decimal "line", precision: 6, scale: 1
    t.datetime "captured_at", null: false
    t.string "source_provider", null: false
    t.boolean "is_closing", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bookmaker_id"], name: "index_odds_snapshots_on_bookmaker_id"
    t.index ["market_id", "is_closing"], name: "index_odds_snapshots_on_market_id_and_is_closing"
    t.index ["market_id", "outcome", "bookmaker_id", "captured_at"], name: "index_odds_snapshots_latest", order: { captured_at: :desc }
    t.index ["market_id"], name: "index_odds_snapshots_on_market_id"
  end

  create_table "picks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "market_id", null: false
    t.string "side", null: false
    t.bigint "bookmaker_id", null: false
    t.integer "price_at_add", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bookmaker_id"], name: "index_picks_on_bookmaker_id"
    t.index ["market_id"], name: "index_picks_on_market_id"
    t.index ["user_id", "market_id", "side", "bookmaker_id"], name: "index_picks_natural_key", unique: true
    t.index ["user_id"], name: "index_picks_on_user_id"
  end

  create_table "player_game_logs", force: :cascade do |t|
    t.bigint "player_id", null: false
    t.bigint "game_id", null: false
    t.bigint "team_id", null: false
    t.bigint "opponent_team_id", null: false
    t.date "game_date", null: false
    t.integer "season", null: false
    t.boolean "home", null: false
    t.decimal "minutes", precision: 5, scale: 2, default: "0.0", null: false
    t.integer "points", default: 0, null: false
    t.integer "rebounds", default: 0, null: false
    t.integer "assists", default: 0, null: false
    t.integer "threes_made", default: 0, null: false
    t.integer "steals", default: 0, null: false
    t.integer "blocks", default: 0, null: false
    t.integer "turnovers", default: 0, null: false
    t.integer "fouls", default: 0, null: false
    t.jsonb "stats", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_player_game_logs_on_game_id"
    t.index ["opponent_team_id", "season"], name: "index_player_game_logs_on_opponent_team_id_and_season"
    t.index ["opponent_team_id"], name: "index_player_game_logs_on_opponent_team_id"
    t.index ["player_id", "game_date"], name: "index_player_game_logs_on_player_id_and_game_date", order: { game_date: :desc }
    t.index ["player_id", "game_id"], name: "index_player_game_logs_on_player_id_and_game_id", unique: true
    t.index ["player_id"], name: "index_player_game_logs_on_player_id"
    t.index ["team_id"], name: "index_player_game_logs_on_team_id"
  end

  create_table "players", force: :cascade do |t|
    t.bigint "sport_id", null: false
    t.bigint "team_id"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "normalized_name", null: false
    t.string "position"
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sport_id", "normalized_name"], name: "index_players_on_sport_id_and_normalized_name"
    t.index ["sport_id"], name: "index_players_on_sport_id"
    t.index ["team_id"], name: "index_players_on_team_id"
  end

  create_table "prop_hit_rates", force: :cascade do |t|
    t.bigint "market_id", null: false
    t.string "side", null: false
    t.decimal "line", precision: 6, scale: 1
    t.decimal "l5", precision: 5, scale: 2
    t.decimal "l10", precision: 5, scale: 2
    t.decimal "l20", precision: 5, scale: 2
    t.decimal "h2h", precision: 5, scale: 2
    t.decimal "season", precision: 5, scale: 2
    t.decimal "prev_season", precision: 5, scale: 2
    t.integer "l5_n"
    t.integer "l10_n"
    t.integer "l20_n"
    t.integer "h2h_n"
    t.integer "season_n"
    t.integer "prev_season_n"
    t.decimal "closing_line_hit_rate", precision: 5, scale: 2
    t.decimal "mean", precision: 7, scale: 2
    t.decimal "median", precision: 7, scale: 2
    t.datetime "computed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["market_id", "side"], name: "index_prop_hit_rates_on_market_id_and_side", unique: true
    t.index ["market_id"], name: "index_prop_hit_rates_on_market_id"
  end

  create_table "raw_payloads", force: :cascade do |t|
    t.string "provider", null: false
    t.string "endpoint", null: false
    t.string "params_digest", null: false
    t.datetime "fetched_at", null: false
    t.integer "status", null: false
    t.jsonb "body", null: false
    t.string "body_sha256", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "endpoint", "params_digest"], name: "index_raw_payloads_on_provider_and_endpoint_and_params_digest"
    t.index ["provider", "fetched_at"], name: "index_raw_payloads_on_provider_and_fetched_at"
  end

  create_table "saved_filters", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "scope", default: "props", null: false
    t.jsonb "params", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_saved_filters_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sports", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_sports_on_key", unique: true
  end

  create_table "teams", force: :cascade do |t|
    t.bigint "sport_id", null: false
    t.string "abbreviation", null: false
    t.string "name", null: false
    t.string "city"
    t.string "conference"
    t.string "division"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sport_id", "abbreviation"], name: "index_teams_on_sport_id_and_abbreviation", unique: true
    t.index ["sport_id"], name: "index_teams_on_sport_id"
  end

  create_table "unresolved_entities", force: :cascade do |t|
    t.string "provider", null: false
    t.string "external_type", null: false
    t.string "external_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "reason", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "external_type", "external_id"], name: "index_unresolved_on_provider_type_and_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false, null: false
    t.string "odds_format", default: "american", null: false
    t.jsonb "enabled_bookmaker_keys"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "defense_ranks", "teams"
  add_foreign_key "games", "sports"
  add_foreign_key "games", "teams", column: "away_team_id"
  add_foreign_key "games", "teams", column: "home_team_id"
  add_foreign_key "insights", "games"
  add_foreign_key "insights", "markets"
  add_foreign_key "markets", "games"
  add_foreign_key "markets", "players"
  add_foreign_key "odds_snapshots", "bookmakers"
  add_foreign_key "odds_snapshots", "markets"
  add_foreign_key "picks", "bookmakers"
  add_foreign_key "picks", "markets"
  add_foreign_key "picks", "users"
  add_foreign_key "player_game_logs", "games"
  add_foreign_key "player_game_logs", "players"
  add_foreign_key "player_game_logs", "teams"
  add_foreign_key "player_game_logs", "teams", column: "opponent_team_id"
  add_foreign_key "players", "sports"
  add_foreign_key "players", "teams"
  add_foreign_key "prop_hit_rates", "markets"
  add_foreign_key "saved_filters", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "teams", "sports"
end
