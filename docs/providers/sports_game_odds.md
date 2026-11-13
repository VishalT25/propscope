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

## Verified against a real response (2026-11-09, free key)
Shape confirmed against real NBA events; the contract spec uses a synthetic stand-in (`spec/fixtures/providers/sports_game_odds/synthetic_shape_sample.json` is a synthetic sample (invented players, no recorded provider data) used by the contract spec):
- statIDs `points`, `rebounds`, `assists`, `threePointersMade`, `points+rebounds+assists` are exactly right. The feed also has `blocks`, `steals`, `turnovers`, `points+rebounds`, `points+assists`, `rebounds+assists`, `doubleDouble`, `firstBasket`, etc. (not modeled yet).
- Prices, `overUnder` and `spread` are strings. Spread lines are in `byBookmaker[...].spread`, totals and props in `.overUnder`.
- `byBookmaker[...].lastUpdatedAt` exists (we store it as `captured_at`), as do `available` and a `deeplink` (we drop deep links).
- `teams.*.names.short` is the abbreviation; `players[id]` has `name`, `teamID`. Names keep accents ("Luka Dončić").
- Period vocabulary: `game`, `1h`, `2h`, `1q`..`4q`, `reg`. Bet types: `ml`, `sp`, `ou`, `yn`, `eo`, `ml3way`. We model only `game` + `ml`/`sp`/`ou`.

## Things the real response taught us
- **Responses are big**: ~1.3MB per event (1,000+ markets). The adapter stores a slimmed payload (modeled markets and fields only) so 14 days of raw payloads stay small.
- **The free key hides some bookmaker odds**: the response carries a `notice` ("Response is missing N bookmaker odds. Upgrade your API key..."). Six to nine books still came back per market, which is enough for best-price.
- Still unconfirmed: the `limit` maximum.

## Terms (summary, not legal advice)
- No reselling, redistribution, data dumps, bulk exports, downloadable files or RSS of the data.
- Showing data to end users inside an app with independent value is allowed; attribution notices stay intact; "powered by SportsGameOdds" is permitted.
- On termination, delete the data within 30 days (aggregated/transformed outputs that cannot reconstruct the data are excluded).
- Consequence for us: **no public JSON/CSV export endpoints**, fixtures stay small, and the demo shows data only through the UI.

## Budget plan
~50 events/day (8 to 10 games, 4 to 5 snapshots each) is roughly 1,500/month, inside the 2,500 limit. `BudgetGuard` caps at 80% for optional snapshots and refuses at 100%.
