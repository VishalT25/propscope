# Self-hosting

Propscope is built to be run by you, with your own API keys. Nothing here takes bets or handles money.

Single-user by default: there is no sign-in. One built-in local user holds your slip, saved filters and preferences. That is safe because the app listens on this computer only (`127.0.0.1`). If you let other machines reach it (`BIND_ADDRESS=0.0.0.0`), anyone who can would be you, so also set `SINGLE_USER=false` to turn accounts on.

## 1. Run it
```
git clone <this repo> && cd propscope
bin/self-host            # needs Docker
```
That creates `.env` with random secrets and builds and starts the app and Postgres. Open http://localhost:3000 (change the port with `PORT=8080 bin/self-host`). A fresh install opens on a **setup page**:

- **Use sample data:** made-up players and odds, ready in seconds, no keys. Good for looking around. It is re-dated each morning so today's slate is always there. You can switch to your own data later in Settings.
- **Use my own data:** the setup page takes you through steps 2 and 3 below.

## 2. Use real data (set up in the app)
You need your own keys (you are responsible for each provider's terms):

| Provider | What for | Free tier | What you really need |
|---|---|---|---|
| [SportsGameOdds](https://sportsgameodds.com) | odds and props | 2,500 events/month, 10 req/min, 9 books | the free key is enough |
| [BallDontLie](https://balldontlie.io) | teams, players, games, box scores | teams, players, games only | **the ALL-STAR plan (about $9.99/month for NBA)** for box scores, which hit rates need |

1. **Keys.** On the setup page, paste both keys and press "Save and test keys". Each key is tested with one tiny request, and the page tells you if a key is rejected or if your BallDontLie plan has no box scores (it needs them, so the free plan can't be used for live data). Keys are stored encrypted in the database, are never shown again (only the last four characters), and an environment variable of the same name (`SPORTSGAMEODDS_API_KEY`, `BALLDONTLIE_API_KEY`) always takes priority if you would rather use `.env`.
2. **History.** Choose one or two seasons (two is best) and start. It runs in the background, with a progress bar, and takes about 25 minutes for two seasons. You can close the page. If it stops (a budget runs out, the app restarts, a provider errors) nothing is lost: start it again and it carries on where it left off.
3. **After that** the scheduled jobs keep everything current. Settings, Data shows your keys (last four characters), how much of each monthly allowance is used, and when history was loaded, and has "Refresh odds now", "Change keys or load more history", and "Switch to sample data".

Prefer the command line? `LIVE_DATA=true` in `.env` with your keys, then `docker compose exec web bin/rails data:backfill_logs SEASONS=2` does the same load, and setup counts it as done.

## 3. The optional model service
```
bin/self-host --model
```
Starts the Python service and points the app at it. It needs a trained model in `model_service/models/points/` (see `model_service/README.md`: export, train, restart). Without a model file the service reports `no_model` and the app simply hides the Model column. Read the README's evaluation section first: it is a small improvement over simple form, not an edge.

To host the model service on Vercel instead, see `docs/deploy-model-service.md`.

## Operating it
- **Logs:** `docker compose logs -f web`
- **Update:** `git pull && docker compose up -d --build` (migrations run on start)
- **Back up the database:** `docker compose exec db pg_dump -U propscope propscope_production > backup.sql`
- **Logos and photos:** Settings (account menu, then "Settings and about") uploads a whole league's team logos and player photos at once, matched by file name. Pick the league, choose all the files in one go, and the page lists what was added and what was skipped and why. Currently NBA only.
  - *Format and size:* PNG, JPEG, WebP or GIF (the contents are checked; SVG is refused), up to 2 MB each. Square images, at least 256 × 256 pixels, look best.
  - *Team logos:* name each file with the team code, any case: `BOS.png`, `lal.webp`.
  - *Player photos:* the player's name in lower case, words joined by hyphens: `jaylen-brown.png`. Accents, punctuation and Jr/Sr/II/III don't matter (`dusan-markovic.png`, `wendell-carter.png`). If two players share a name, add the team code after an underscore: `jaylen-brown_BOS.png`.
  - Settings has a CSV of the exact file name for every team and player (and whether it already has an image). Uploading for someone who already has an image replaces it.
  - Files live in the `uploads` Docker volume, so they survive `up --build`; back that volume up with the database. Only an admin can change images (the one local user is an admin in single-user mode). Until you add one, everything gets a generated monogram. Upload only images you have the right to use.
- **Version and git info:** the About section shows `VERSION` and the git commit and branch. A Docker image has no `.git`, so to show them pass `GIT_SHA`, `GIT_BRANCH`, `GIT_COMMITTED_AT` (ISO 8601) and optionally `BUILD_TIME` as environment variables (the Compose file passes them through), for example `GIT_SHA=$(git rev-parse HEAD) GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) GIT_COMMITTED_AT=$(git log -1 --format=%cI) docker compose up -d --build`. Without them the About section simply says git details are not available.
- **Admin / budget:** usage is stored in `api_usages`; see `docs/operations.md` for jobs and rake tasks.
- **Run on a server:** the same Compose file works on any VPS. Put a reverse proxy with HTTPS (Caddy, nginx) in front of port 3000. A Kamal config is scaffolded in `config/deploy.yml` but has not been tested.

## Free public demo (optional)
A demo on sample data needs no keys, no data budget and no provider terms. Any host that runs a Docker image and Postgres works; free tiers usually sleep when idle and may expire databases, so check them before relying on one. I have not tested a specific host.
