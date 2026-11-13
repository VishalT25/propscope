# Contributing

Thanks for taking a look. Issues and pull requests are welcome.

## Getting set up
```bash
bundle install && bin/rails db:create db:migrate db:seed
bin/dev                       # http://localhost:3000, sample data
bundle exec rspec && bin/rubocop && bin/brakeman
```
You don't need any API keys: development and tests use the fixture provider and never touch the network.

## Ground rules
- **No live API calls in tests or dev by default.** Live calls only with `LIVE_DATA=true`.
- **No scraping and no private APIs.** Documented provider APIs through the adapters in `app/providers`.
- **No third-party branding.** Sportsbooks are text badges, never logos.
- **No `Float` for odds, probabilities or stakes.** Use `BigDecimal` and integer American odds.
- **Time:** store UTC, display America/Toronto.
- **Plain-Ruby services** under `app/services/<area>/`, thin controllers and jobs, `Data.define` for value objects. Pages read from our database, never from an external API.
- **No new gems** without discussing it in an issue first.
- **Secrets** live in ENV or credentials, never in the repo. Keep `.env.example` current.

## Pull requests
1. Keep them small and focused; one logical change per commit with a clear message.
2. Add or update specs. `bundle exec rspec`, `bin/rubocop` and `bin/brakeman` must pass; CI runs them.
3. For UI changes, include a screenshot.

By contributing you agree your work is released under the [MIT license](LICENSE).
