# Propscope: working rules

Read `PROJECT_SPEC.md` (product/architecture) and `outlier-product-ux-audit.md` (UX reference). The spec wins on scope: same structure and UX as the reference product, but our own name, brand, colours and copy.

`legacy-next/` is the archived Next.js prototype. Reference only; do not edit or build on it.

1. Work one phase at a time. Start each phase with a short plan. End it with the full test suite and RuboCop, a summary, open decisions, then **stop for review**.
2. Never call live third-party APIs in tests or dev by default. Use the fixture provider. Live calls only with `LIVE_DATA=true`.
3. No scraping or reverse-engineering private APIs. Documented APIs through provider adapters only.
4. No third-party branding: no sportsbook logos or other products' names, logos, copy or colours. Books are text badges (short code + name).
5. Ask before adding gems not listed in spec Section 3. Prefer Rails built-ins.
6. Never use `Float` for odds, probabilities or stakes. Use `BigDecimal` / Postgres `numeric` / integer American odds.
7. Store time in UTC; convert to `America/Toronto` in views only. Slate date = game's local date in US Eastern.
8. Secrets in credentials or ENV, never committed. Keep `.env.example` current.
9. Small, logical commits with clear messages.
10. If a requirement is ambiguous or looks wrong once in code, ask rather than guess.

Conventions: business logic in plain-Ruby service objects under `app/services/<area>/`; thin jobs and controllers; `Data.define` value objects; pages read only from our DB, never from external APIs.
