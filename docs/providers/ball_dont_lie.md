# BallDontLie (teams, players, games, box scores)

Researched 2026-11-09 from docs.balldontlie.io. Canonical source for NBA teams, players and games.

| Tier | Price | Rate | Includes |
|---|---|---|---|
| Free | $0 | **5 req/min** | Teams, Players, Games |
| ALL-STAR | $9.99/mo per league | 60 req/min | + **Game Player Stats (`/v1/stats`)** |
| GOAT | $39.99/mo per league | 600 req/min | + Box Scores, advanced |

## Budget decision (needs the owner)
Hit rates, defense ranks and insights need per-game player stats, so **live data needs ALL-STAR ($9.99/mo)**. That is the only paid item and still fits the ≤ $10/month budget. Until a paid key is set, the app runs entirely on fixtures. The nightly ingest and backfill use `/v1/stats`; they will return 401 on a free key.

## API shape we code against
- Base `https://api.balldontlie.io/v1`, `Authorization: <key>` (no `Bearer`).
- Cursor pagination: `meta.next_cursor`, `per_page` max 100. On `/stats` the cursor key is omitted at the end; a full page may be followed by an empty one (we stop on a blank cursor or empty data).
- `/teams`, `/players/active`, `/games?start_date&end_date`, `/stats?dates[]=YYYY-MM-DD`.
- Stats fields: `min` (string like "34:12"; blank/"00" = DNP), `pts reb ast stl blk turnover pf fg3m ...`, nested `player`, `team`, `game` (with `home_team_id`, `visitor_team_id`).
- A scheduled game's `status` is its ISO start time; finished is `"Final"`.

## What a real key told us (2026-11-09)
- A free key returned 200 for `/teams`, `/games`, `/players` and **401 for `/players/active` and `/stats`**. Live stats and the active-players list need the ALL-STAR plan.
- `/teams` returns **89 teams**: the 30 real ones plus ~59 defunct franchises with a blank conference (two reuse `WAS`). The adapter keeps only teams with a conference.
- Game `date` is the US Eastern date; `datetime` is UTC. Scheduled games have `status` = ISO start time, finished ones `"Final"` (plus `status_state`).
- **Verified with an ALL-STAR key (same day):** `/stats` and `/players/active` return 200 and match the parser exactly (`min` is "MM:SS", stats are `pts reb ast fg3m stl blk turnover pf ...`, nested `player`/`team`/`game` with `home_team_id` and `visitor_team_id`). Contract specs: `spec/providers/real_shape_bdl_spec.rb`.

## Backfill cost
`data:backfill_logs SEASONS=2` makes ~one call per day with games (more when a day has over 100 rows) at 5 req/min on free or 60 on ALL-STAR. On ALL-STAR it takes roughly 10 to 20 minutes. It is resumable (skips days already loaded).

## Terms
The pages read did not cover storing or redistributing data; confirm with the provider before a public launch.
