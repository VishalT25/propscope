# Deploying the model service on Vercel

Vercel runs FastAPI as a serverless function. The serving install is small (`requirements.txt` is serving-only and uses `xgboost-cpu`, which has no GPU libraries; about 180 MB installed on macOS and smaller on Linux, under Vercel's 250 MB function limit at the time of writing; re-check the current limit).

## Steps
1. Train a model locally (see `model_service/README.md`) so `model_service/models/points/{model.json,meta.json}` exist. They are git-ignored on purpose (derived from your data), so deploy from your machine with the CLI, which uploads local files:
```
cd model_service
npm i -g vercel
vercel login
vercel deploy --prod
```
2. Protect it. A Vercel URL is public, so set a shared secret in the Vercel project settings (`MODEL_API_KEY`) and the same value in your Rails environment. The service then requires an `X-Api-Key` header on `/predict` and `/model` (`/health` stays open).
3. Point Rails at it: `MODEL_SERVICE_URL=https://<your-project>.vercel.app` and `MODEL_API_KEY=<the secret>`.
4. Check: `curl https://<your-project>.vercel.app/health` should report `model_loaded: true`.

## What to expect
- **Cold starts** add a second or so. `ModelClient` has a 5 second timeout and a circuit breaker, so a slow start costs one skipped run at worst.
- **Retraining:** train locally and redeploy. The deployment is the model; there is nothing to sync.
- **The Rails app is not on Vercel.** It needs a long-running process for its scheduled jobs. Use `docs/self-hosting.md`.
