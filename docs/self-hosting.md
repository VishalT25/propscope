# Self-hosting

Propscope is built to be run by you, with your own API keys. Nothing here takes bets or handles money.

Single-user by default: there is no sign-in. One built-in local user holds your slip, saved filters and preferences. If you share a deployment, set `SINGLE_USER=false` to turn accounts back on.

## 1. Run it with sample data (no keys, about 5 minutes)
```
git clone <this repo> && cd propscope
bin/self-host            # needs Docker
```
That creates `.env` with random secrets, builds and starts the app and Postgres, and loads a synthetic sample slate (fictional players). Open http://localhost:3000. Change the port with `PORT=8080 bin/self-host`.

## 2. Use real data
You need your own keys (you are responsible for each provider's terms):

| Provider | What for | Free tier | What you really need |
|---|---|---|---|
| [SportsGameOdds](https://sportsgameodds.com) | odds and props | 2,500 events/month, 10 req/min, 9 books | the free key is enough |
| [BallDontLie](https://balldontlie.io) | teams, players, games, box scores | teams, players, games only | **the ALL-STAR plan (about $9.99/month for NBA)** for box scores, which hit rates need |

1. Put the keys in `.env` (`SPORTSGAMEODDS_API_KEY`, `BALLDONTLIE_API_KEY`).
2. `bin/self-host --live` (sets `LIVE_DATA=true`).
3. Load history once (about 20 minutes for two seasons on the paid BallDontLie rate; resumable):
```
docker compose exec web bin/rails data:backfill_logs SEASONS=2
docker compose exec web bin/rails runner 'SnapshotOddsJob.perform_now("morning")'
```
After that the scheduled jobs keep it current. On the free BallDontLie plan, set `min_interval: 12.5` for `balldontlie` in `config/providers.yml` (5 requests/minute).

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
- **Logos and photos:** Settings (account menu, then "Settings and about") lets you upload a logo per team and a photo per player: PNG, JPEG, WebP or GIF, up to 2 MB. Files live in the `uploads` Docker volume, so they survive `up --build`; back that volume up with the database. Only an admin can change them (the one local user is an admin in single-user mode). Until you add one, everything gets a generated monogram. Upload only images you have the right to use.
- **Version and git info:** the About section shows `VERSION` and the git commit and branch. A Docker image has no `.git`, so to show them pass `GIT_SHA`, `GIT_BRANCH`, `GIT_COMMITTED_AT` (ISO 8601) and optionally `BUILD_TIME` as environment variables (the Compose file passes them through), for example `GIT_SHA=$(git rev-parse HEAD) GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD) GIT_COMMITTED_AT=$(git log -1 --format=%cI) docker compose up -d --build`. Without them the About section simply says git details are not available.
- **Admin / budget:** usage is stored in `api_usages`; see `docs/operations.md` for jobs and rake tasks.
- **Run on a server:** the same Compose file works on any VPS. Put a reverse proxy with HTTPS (Caddy, nginx) in front of port 3000. A Kamal config is scaffolded in `config/deploy.yml` but has not been tested.

## Free public demo (optional)
A demo on sample data needs no keys, no data budget and no provider terms. Any host that runs a Docker image and Postgres works; free tiers usually sleep when idle and may expire databases, so check them before relying on one. I have not tested a specific host.
