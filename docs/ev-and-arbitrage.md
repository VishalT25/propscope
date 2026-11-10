# EV+ and Arbitrage

Both read only our own tables (current snapshots), never an external API. `TwoWayMarkets` is the shared starting point: it finds every two-sided market on upcoming games (props and totals: over/under; moneyline: home/away; spread: home at L with away at -L) and each side's CURRENT price per book (a book's latest snapshot across all lines, so a superseded line never counts).

## Fair price (`Ev::FairPrice`)
1. If a book flagged `sharp` quotes both sides, remove its vig and use that.
2. Otherwise average the no-vig probability across every book quoting both sides (at least `min_books`, default 3). **The free data tier has no sharp book, so this is the consensus**, and the UI says so.

Devig methods (from the `odds_math` gem): multiplicative (fast) and power (solves for an exponent per book; cold ~7s over a full slate, then cached against the exact snapshot ids).

## EV and Kelly
`EvCalculator`: EV = fair probability x decimal odds - 1; Kelly = EV / (odds - 1) scaled by the multiplier (quarter by default). The offered price is the best EV among the books the viewer enabled; the fair price is always built from all books. The sharp book is never offered against its own fair price. EV is an edge on paper under the model's assumptions, not a promise of profit.

## Arbitrage
`ArbitrageFinder`: best price per side across the enabled books, at two different books, with total implied probability under 100%. `OddsMath::Arbitrage.split` divides a stake into whole cents so the payouts match as closely as whole cents allow (within a cent at typical odds, a couple of cents at long odds) and the stakes sum exactly to the total.

## Sample data
The synthetic fixtures add random noise across books plus six deliberate arbitrages, so the demo shows far more arbitrage than a real feed ever would.
