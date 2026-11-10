# Model service (optional)

A small FastAPI service that projects a player's stat and turns it into over/under probabilities. **The Rails app works fully without it**: if `MODEL_SERVICE_URL` is blank, or the service is down, the "Model" column simply does not appear.

## What it predicts
It predicts the player's **points** from their prior form (L5/L10/L20/season averages, spread, minutes, shot volume), rest and back-to-backs, home/road, and the team scoring environment. Rails computes the features from our database (`app/services/model_features.rb`, the single source of truth); this service only evaluates the model. Because we store no historical betting lines, the model learns the stat itself rather than "over the line"; `app/probability.py` then turns a projection and spread into P(over), P(under) and P(push) for any line (whole-number lines can push; half-points cannot).

## Run it
```
cd model_service
python3.13 -m venv .venv && ./.venv/bin/pip install -r requirements.txt   # macOS: brew install libomp for XGBoost
cd .. && bin/rails model:export                                           # needs real box scores (data:backfill_logs)
cd model_service && ./.venv/bin/python train.py --data ../tmp/model/points.csv --out models/points
./.venv/bin/uvicorn app.main:app --port 8000
MODEL_SERVICE_URL=http://localhost:8000 bin/rails runner 'PredictPropsJob.perform_now'
./.venv/bin/python -m pytest
```

## Endpoints
- `GET /health`: `{status, model_loaded, model_version}`
- `GET /model`: version, feature list, training metrics
- `POST /predict`: `{rows: [{id, line, features}]}` (max 500) returns `{model_version, predictions: [{id, projection, std, p_over, p_under, p_push}]}`

## How Rails calls it
`ModelClient` (Faraday): 1s connect / 5s read timeout, batches of 200, and a circuit breaker (3 failures in a row pause calls for 5 minutes, so jobs skip instantly instead of waiting on timeouts). `PredictPropsJob` stores `predictions(market_id, side, probability, projection, model_version)` and never raises when the service is unavailable; the last good predictions stay in place.

## How good is it? (measured, not hoped)
First real run (2026-11-10): 2 seasons of NBA box scores, 26,582 training rows, time-ordered 70/15/15 split, points only.

| | MAE (points) |
|---|---|
| Model (test: May to Nov 2026, playoffs plus a new season) | **4.75** |
| Last-10 average | 4.85 |
| 50/50 blend of L10 and season average | 4.75 |
| Model on the validation window (regular season) vs L10 | 4.78 vs 4.96 |

Over/under skill is measured on lines synthesised from the L10 mean (we store no historical lines): Brier 0.2427 for the model vs 0.2450 for the base rate and 0.2492 for a normal approximation from L10. Lower is better.

**Reading it honestly:** a small, real improvement over naive form (about 2 to 4 percent on projection error), and no better than simply blending recent and season averages. It is **overconfident at the high end** (when it says 64 to 73 percent, the observed rate on the proxy lines was 50 to 55 percent), partly because the proxy lines are not real book lines. It has never been compared with a real sportsbook line. **Treat the Model column as research, not advice, and do not size bets from it.** The service stays off unless you set `MODEL_SERVICE_URL`.

Things that would plausibly help, not yet done: real historical closing lines as features and as the evaluation target, injury and lineup data, a model per stat, and recalibration of the probabilities (isotonic or Platt) on held-out real lines.
