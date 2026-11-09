# SportsGameOdds (odds + props)

Researched 2026-11-09 from sportsgameodds.com (pricing, docs, terms). Re-check before launch; plans change.

| | Free (Amateur) | Rookie $99/mo |
|---|---|---|
| Requests | 10 / min | 50 / min |
| Monthly allowance | **2,500 objects** (1 object = 1 event returned) | 100k |
| Update delay | 10 min | 3 min |
| Leagues | NFL NBA MLB NHL NCAAF NCAAB UCL MLS | 17 |
| Books | FanDuel, DraftKings, BetMGM, Caesars, ESPN BET, Bovada, Unibet, PointsBet, William Hill | 77 |

**No sharp book (Pinnacle) on free.** EV+ (Phase 6) therefore uses a no-vig *market-consensus* fair price and says so in the UI.

## API shape we code against
- `GET https://api.sportsgameodds.com/v2/events` (`X-Api-Key` header). Params: `leagueID=NBA`, `oddsAvailable=true`, `startsAfter/startsBefore`, `eventIDs`, `cursor`, `limit`.
- Billing is **per event returned**, whatever the markets or books. One event = every market and book for the game.
- `oddID = statID-statEntityID-periodID-betTypeID-sideID`, e.g. `points-home-game-ml-home`, `points-all-game-ou-over`, `assists-<PLAYER_ID>-game-ou-over`.
- `odds[oddID].byBookmaker[bookKey] = { odds: "-110", overUnder: "24.5", spread: "-3.5", available: true }`. Prices and lines are strings.
- `players[playerID] = { teamID, name, firstName, lastName }`, `teams.{home,away} = { teamID, names: { long, medium, short } }`, `status.startsAt`.

## Unverified assumptions (confirm on the first live capture)
- Exact `statID` names for threes and PRA (`threePointersMade`, `points+rebounds+assists`): see `STAT_TO_MARKET` in `app/providers/providers/sports_game_odds.rb`.
- Whether spread lines live in `byBookmaker[...].spread` (we also fall back to `overUnder`).
- `lastUpdatedAt` per bookmaker (we fall back to fetch time).
- `limit` maximum, and `names.short` being the team abbreviation (resolver falls back to full name).

## Terms (summary, not legal advice)
- No reselling, redistribution, data dumps, bulk exports, downloadable files or RSS of the data.
- Showing data to end users inside an app with independent value is allowed; attribution notices stay intact; "powered by SportsGameOdds" is permitted.
- On termination, delete the data within 30 days (aggregated/transformed outputs that cannot reconstruct the data are excluded).
- Consequence for us: **no public JSON/CSV export endpoints**, fixtures stay small, and the demo shows data only through the UI.

## Budget plan
~50 events/day (8 to 10 games, 4 to 5 snapshots each) is roughly 1,500/month, inside the 2,500 limit. `BudgetGuard` caps at 80% for optional snapshots and refuses at 100%.
