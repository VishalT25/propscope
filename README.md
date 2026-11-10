# Propscope

Open-source, self-hostable sports prop research tool (NBA first). Windowed hit rates (L5/L10/L20/H2H/season), best price across books, filters, insights. It never takes bets or handles money.

Built with Rails 8, Hotwire, Tailwind, PostgreSQL, Solid Queue. See `PROJECT_SPEC.md` for the product and phases and `outlier-product-ux-audit.md` for the UX reference.

## Setup
```
brew install rbenv ruby-build postgresql@17   # macOS
rbenv install 3.4.12
bundle install
bin/rails db:create db:migrate db:seed   # sample slate, no API keys needed
bin/dev
```
Open http://localhost:3000 (design reference at `/styleguide` in development).

Live data stays off unless `LIVE_DATA=true`; copy `.env.example` to `.env` for API keys.

## Checks
```
bundle exec rspec
bin/rubocop
bin/brakeman --no-pager
```

## Layout
- `gems/odds_math`: BigDecimal odds conversions, devig, EV and Kelly (standalone gem).
- `legacy-next/`: archived Next.js prototype (not part of the build, git-ignored).

## Data
Jobs fetch, pages read: a page request never calls an external API. Dev and test run on synthetic fixtures through the real adapters' parsers; live calls need `LIVE_DATA=true` and your own API keys (you are responsible for each provider's terms). See `docs/providers/`, `docs/data-model.md`, `docs/operations.md`.

## Status
Phase 0 (odds_math), Phase 1 (skeleton, auth, design tokens, American/decimal toggle) Phase 2 (data layer: models, provider adapters, entity resolution, budget guard, ingestion jobs, fixtures) and Phase 3 (hit rates, defence ranks, best price, props explorer with filters, live count, sort, pagination, saved filters, book selector) complete. Phase 4 (prop detail page: hero, stat tabs, window pills, closing-line chart, supporting stats, defence table, same-position history, line movement) complete. Next: Phase 5 (games, game page, insights, My Picks). 
