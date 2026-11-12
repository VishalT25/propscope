# Opening a slip at a sportsbook

What works, what does not, and how we know. Findings are from hand tests on 2026-11-11 and 2026-11-12 (Ontario, FanDuel and DraftKings, desktop and phone) unless marked otherwise.

## What we do
The slip offers **Add all N legs to FanDuel** (a link), **Copy link** and a **QR code** to scan with a phone. They open FanDuel with the picks already in the bet slip. Nothing is placed for you. The address depends on **Region** (account menu): `on.sportsbook.fanduel.ca` for Ontario, `sportsbook.fanduel.com` for the United States. Sportsbooks are licensed per province and per state, so the site, the app listing and the books that exist at all differ by place; more regions are added when their address has been checked.

## FanDuel (works)
- Format: `https://<host>/addToBetslip?marketId[0]=…&selectionId[0]=…&marketId[1]=…&selectionId[1]=…`
- The ids are the ones SportsGameOdds gives per price (`marketId` like `42.624795660`, `selectionId` a number). They are the same across the US and Ontario sites (a market id from our US-sourced data matched one in a link generated for Ontario).
- **Use the indexed form even for one leg.** The plain form SportsGameOdds supplies (`marketId=…&selectionId=…`) works on desktop but fails on a phone; the indexed form works on both.
- On a phone the link opens FanDuel's mobile web slip, which says you need the app to bet. Scanning the QR code from the camera (a link from outside the browser) may hand over to the app; not confirmed.
- No partner or affiliate tag is added. Outlier's links carry `shareBetId=partner_outlier`, which is its own partner tag and must not be copied. FanDuel does not publish documentation for this format that we could find; it is observed behaviour and could change.

## DraftKings (does not work, so it is left out)
- Format seen on a partner's multi-leg link: `https://sportsbook.draftkings.com/event/<event id>?outcomes=<token>+<token>`, legs joined by `+`.
- The event ids SportsGameOdds gives us are right (one per game, and one matched a partner link). The **outcome token** is the problem: for a standard prop it is the short form `0QA…`, identical for the Over and the Under, so it names the market but not the side. DraftKings answers "technical error, pick could not be added" on a phone and "one or more of your picks are no longer available" on desktop, for a single leg and for several.
- The long form a partner uses (`0QA…#…_13L…Q1-2…Q20`) carries the selection. We held none for the day's props, only for a minority of Under legs from earlier games. We have links for only a few games per day.
- Revisit if SportsGameOdds (or another provider) supplies selection-level tokens. Ask them.

## Other books
- BetMGM and Caesars: links are New Jersey addresses (`/us/nj/`, `www.nj.betmgm.com`), single selection, untested; useless in Ontario. Not offered.
- No links at all for Bovada, PointsBet, Unibet or William Hill.

## What the providers document
- SportsGameOdds: a deeplink is "a per-selection handoff that opens that single market" and "is not guaranteed to prefill a full multi-leg slip". No multi-leg parameter is documented.
- Vendors that sell multi-leg slip links (for example SharpSports' betPlace, `…/place/parlay/<book>?marketSelection=…`) use their own ids and look commercial; pricing and coverage are not public.

## bet365
SportsGameOdds lists bet365 as a bookmaker, but it is not among the nine books of the free tier (FanDuel, DraftKings, BetMGM, Caesars, ESPN BET, Bovada, Unibet, PointsBet, William Hill). Its page does not say which paid plan includes it, whether it carries player props, or whether it works in Ontario, and bet365 has no public API of its own. Ask SportsGameOdds before paying for a plan for it.
