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

## Honesty about the model
`train.py` evaluates on a time-ordered holdout against baselines (L10 mean, a normal approximation from L10, a coin flip) and prints calibration. It is evaluated on lines synthesised from the L10 mean, not real lines, so it measures whether the projection is better than simple form, not whether it beats a sportsbook. Treat it as research, not advice.
