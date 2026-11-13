<div align="center">

<img src="docs/banner.svg" alt="Propscope" width="100%">

<br>

**An open-source, self-hosted research tool for NBA player props.**
Find the props with history on their side, at the best price, and keep it all on your own machine.

<br>

[![CI](https://github.com/VishalT25/propscope/actions/workflows/ci.yml/badge.svg)](https://github.com/VishalT25/propscope/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-4fd9b5.svg)](LICENSE)
![Rails 8](https://img.shields.io/badge/Rails-8-CC0000?logo=rubyonrails&logoColor=white)
![Ruby 3.4](https://img.shields.io/badge/Ruby-3.4-CC342D?logo=ruby&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/self--host-Docker-2496ED?logo=docker&logoColor=white)

</div>

<br>

![Props explorer](docs/screenshots/props.jpg)

> **A research tool, not betting advice.** Propscope never takes bets, never handles money and never touches your sportsbook account. Hit rates describe the past; they don't promise the future. If gambling is a problem for you, help is available (US: 1-800-GAMBLER, Canada: ConnexOntario 1-866-531-2600).

## The idea

Every night there are hundreds of player props on the board ("Over 24.5 points", "Under 5.5 assists"). The question I actually care about is simple: **which of these have real history on their side, at the best price I can get?**

Answering that by hand means flipping between box scores, a few sportsbook apps and a calculator. So I built the thing I wanted open in a tab: every prop, the best price across your books, how often it has cleared the line over several windows, and what the opponent usually allows. Self-hosted, with your own API keys, so nothing about how you use it leaves your computer.

## What it does

| | |
|---|---|
| 🔎 **Props explorer** | Every available prop with the best price across the books you pick, implied probability, opponent matchup, and heat-tinted hit rates (L5, L10, L20, vs this opponent, this season, last season). Live-updating filters, sorting, saved filters, shareable URLs. |
| 📊 **Prop detail** | Per-game bars against the line with each game's closing line overlaid, supporting stats, defence vs position, same-position history against the opponent, and line movement. |
| 🏀 **Games** | The slate with lines and hit strips, plus a page per game: odds, insights, matchup. |
| 💡 **Insights** | Plain-English streaks and splits attached to a pick, ranked by strength. |
| 💸 **EV+ and Arbitrage** | Devigged fair price (a sharp book if you configure one, otherwise a market consensus), EV and Kelly. Two-book arbitrage with whole-cent stake splits. |
| 🎟️ **Slip builder** | Add legs with the +, pick a book, and see every leg at that book's price with combined odds and payout. See which single book pays most for the whole slip. Alternate lines included. |
| 🏠 **Home and saved slips** | Save a slip as a snapshot (book, stake, each leg's price). Legs are graded from box scores already in your database: hit, miss, push, or void for a DNP or postponed game. |
| 🧠 **Optional model** | A small XGBoost projection service, honestly evaluated (including where it falls short). Fully optional. |

American or decimal odds, dark and light themes, and no accounts: a self-hosted copy is single-user by default.

<table>
  <tr>
    <td><img src="docs/screenshots/detail.jpg" alt="Prop detail"></td>
    <td><img src="docs/screenshots/games.jpg" alt="Games"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/insights.jpg" alt="Insights"></td>
    <td><img src="docs/screenshots/ev.jpg" alt="EV+"></td>
  </tr>
</table>

<sub>Screenshots use the bundled sample data: fictional players, made-up odds.</sub>

## Run it

```bash
git clone https://github.com/VishalT25/propscope.git && cd propscope
bin/self-host        # Docker: the app + Postgres
```

Open **http://localhost:3000**. A fresh install lands on a setup page: try the **sample data** straight away, or add your own API keys and load your history (it tests the keys, shows progress and resumes if interrupted). The app only listens on your own machine by default. Full guide: **[docs/self-hosting.md](docs/self-hosting.md)**.

## Data, API keys and terms

You bring your own keys, and you're responsible for following each provider's terms.

| Provider | Used for | Notes |
|---|---|---|
| [SportsGameOdds](https://sportsgameodds.com) | Odds and props | The free tier (2,500 events a month) is enough, and the app budgets itself to stay inside it. Their terms forbid bulk export and redistribution, so Propscope only shows data in its own UI and has no export endpoint. |
| [BallDontLie](https://balldontlie.io) | Teams, players, games, box scores | Box scores need a paid plan (ALL-STAR, about $9.99/month for NBA at the time of writing). |

No scraping and no private APIs. Sportsbooks appear as plain text badges, never logos, and team and player icons are generated monograms. Propscope isn't affiliated with any sportsbook or data provider.

## How it's built

Jobs fetch, pages read: a page request **never** calls an external API.

```text
Provider adapters ─▶ ingestion jobs ─▶ PostgreSQL ─▶ plain-Ruby services ─▶ precompute jobs ─▶ Hotwire pages
                                                                          └▶ optional Python model service
```

A few decisions I cared about:

- **Plain-Ruby services, thin controllers and jobs.** One public method each, value objects with `Data.define`. Easy to test and easy to read.
- **Adapters are the only code that knows a vendor's format.** A fixture provider replays recorded-shape JSON through the same parsers, so dev and CI cost nothing and can never hit a live API.
- **Raw payloads are stored before parsing.** A parser bug gets fixed and re-run from stored data, with no API budget spent twice.
- **Append-only odds, change-only inserts.** Line movement and closing lines fall out of simple queries.
- **Entity resolution skips rather than guesses.** An unmatched player is recorded for review, never silently attached to the wrong record.
- **No `Float` for odds, probabilities or stakes.** `BigDecimal` and integer American odds throughout. The [`odds_math`](gems/odds_math) gem (odds conversions, devig, EV, Kelly, arbitrage) is standalone.
- **Honest numbers.** Small samples are muted, pushes and DNPs are excluded and explained, EV is labelled an edge *on paper*, and the model's evaluation is documented as it is.
- **Optional means optional.** The model service can be absent or down and nothing else changes.

More in **[docs/architecture.md](docs/architecture.md)**, [docs/data-model.md](docs/data-model.md), [docs/ev-and-arbitrage.md](docs/ev-and-arbitrage.md) and [docs/operations.md](docs/operations.md).

## Tech stack

<p>
  <img src="https://skillicons.dev/icons?i=rails,ruby,postgres,tailwind,js,docker,githubactions,python,fastapi&theme=dark" alt="Rails, Ruby, PostgreSQL, Tailwind CSS, JavaScript, Docker, GitHub Actions, Python, FastAPI">
</p>

Rails 8 (Hotwire, importmap), PostgreSQL, Solid Queue and Solid Cache, Tailwind CSS 4 with daisyUI 5 (OKLCH themes), Chart.js, Faraday, RSpec, FactoryBot, WebMock and VCR, RuboCop (omakase), Brakeman, GitHub Actions. Optional model service: Python 3.13, FastAPI, XGBoost.

## Development

```bash
brew install rbenv ruby-build postgresql@17          # macOS
bundle install && bin/rails db:create db:migrate db:seed
bin/dev                                              # http://localhost:3000, sample data
bundle exec rspec && bin/rubocop && bin/brakeman     # tests and checks
cd model_service && pip install -r requirements-dev.txt && python -m pytest
```

Nothing touches the network in development or tests unless you set `LIVE_DATA=true`; everything is served by the fixture provider.

```text
app/providers    adapters, DTOs, registry, fixture provider
app/services     plain-Ruby domain services and ingestion
app/queries      the props explorer query object
app/jobs         thin jobs (see docs/operations.md)
gems/odds_math   odds conversions, devig, EV, Kelly, arbitrage
model_service/   optional FastAPI + XGBoost service
```

## Contributing

Issues and pull requests are welcome. Please read **[CONTRIBUTING.md](CONTRIBUTING.md)** first, and **[SECURITY.md](SECURITY.md)** if you've found a vulnerability.

## License

MIT. See [LICENSE](LICENSE).

<div align="center"><sub>Built by <a href="https://github.com/VishalT25">Vishal Thamaraimanalan</a>. Made for people who like checking the numbers.</sub></div>
