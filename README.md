# Propscope

Open-source, self-hostable sports prop research tool (NBA first). Windowed hit rates (L5/L10/L20/H2H/season), best price across books, filters, insights. It never takes bets or handles money.

Built with Rails 8, Hotwire, Tailwind, PostgreSQL, Solid Queue. See `PROJECT_SPEC.md` for the product and phases and `outlier-product-ux-audit.md` for the UX reference.

## Setup
```
brew install rbenv ruby-build postgresql@17   # macOS
rbenv install 3.4.12
bundle install
bin/rails db:create db:migrate
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

## Status
Phase 0 (odds_math) and Phase 1 (skeleton, auth, design tokens, American/decimal odds toggle) complete.
