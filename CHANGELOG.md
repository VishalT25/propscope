# Changelog

All notable changes. Versions follow [Semantic Versioning](https://semver.org/).

## 0.10.0: first public release
- Props explorer with best price across your books, implied probability, opponent matchup and hit rates (L5, L10, L20, vs opponent, season, last season); live filters, sorting, saved filters, shareable URLs.
- Prop detail with per-game bars, closing lines, supporting stats, defence vs position and line movement.
- Games and per-game pages, plain-English insights, EV+ and two-book arbitrage.
- Slip builder with per-book pricing, saved slips on Home, and automatic grading from stored box scores.
- First-run setup page: sample data or your own SportsGameOdds and BallDontLie keys, with a resumable history backfill.
- Single-user by default, listening on `127.0.0.1`; optional accounts with `SINGLE_USER=false`.
- Docker self-hosting (`bin/self-host`) and an optional XGBoost model service.
