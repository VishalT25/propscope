# Data model

All times UTC. `slate_date` is the game's date in US Eastern. Odds are integer American odds plus `decimal_odds numeric(8,4)`; probabilities are never stored as floats.

| Table | Notes |
|---|---|
| `sports`, `teams`, `players`, `games` | Canonical records (BallDontLie). `players.normalized_name` comes from `NameNormalizer` (accents, suffixes, hyphens, nicknames). `games.season` is the start year (2026 = 2026-27). Unique per `(sport, home, away, slate_date)`. |
| `external_ids` | `(provider, external_type, external_id)` → canonical record. How odds providers are mapped onto canonical rows. |
| `unresolved_entities` | Anything the `EntityResolver` could not match. Skipped, never guessed. `resolved_at` is set once a later run matches it. |
| `bookmakers` | `code` is the text badge. `kind`: sportsbook / dfs / exchange / prediction. `sharp` marks reference books for devig. |
| `markets` | One row per `(game, player?, market_type, period, line, is_alternate)` (unique, `NULLS NOT DISTINCT`). A moved line is a new market, so line movement is a query across sibling markets. |
| `odds_snapshots` | **Append-only.** A row is inserted only if price or line changed for `(market, outcome, bookmaker)`. Only `is_closing` may be updated: set on the last snapshot at or before tip-off. |
| `player_game_logs` | One row per player-game. `minutes = 0` is a DNP and never counts in hit rates (`played` scope). `stats` jsonb holds extra provider fields. |
| `prop_hit_rates`, `defense_ranks`, `insights` | Precomputed (Phase 3+), each with `computed_at`. |
| `saved_filters`, `picks` | Per-user features (Phase 3, 5). `picks.price_at_add` is American odds. |
| `raw_payloads` | Every external response, stored before parsing; 14-day retention; enables `data:renormalize`. |
| `api_usages` | Units used per provider per `YYYY-MM`; `units_limit` null means rate-limited only. |
