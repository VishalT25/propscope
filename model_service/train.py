"""Train the projection model from the CSV that `bin/rails model:export` writes.

    python train.py --data ../tmp/model/points.csv --out models/points

Predicts the player's stat (points) from their prior form and context; the service converts that into over/under
probabilities for any line. Honest evaluation on a time-ordered holdout against simple baselines.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from math import erf, sqrt
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

from app.features import FEATURES

N_STD_BINS = 6


def _norm_cdf(x, mean, std):
    return 0.5 * (1.0 + np.vectorize(erf)((x - mean) / (std * sqrt(2.0))))


def _proxy_lines(df: pd.DataFrame) -> np.ndarray:
    """A stand-in for a book line (we have no historical lines): the trailing L10 mean, nudged to the nearest x.5."""
    return np.floor(df["mean_l10"].to_numpy()) + 0.5


def _p_over(mean, std, line):
    return 1.0 - _norm_cdf(line, mean, np.maximum(std, 1.0))


def _scores(p, y_over):
    p = np.clip(p, 1e-4, 1 - 1e-4)
    return {"brier": float(np.mean((p - y_over) ** 2)),
            "log_loss": float(-np.mean(y_over * np.log(p) + (1 - y_over) * np.log(1 - p))),
            "accuracy": float(np.mean((p > 0.5) == (y_over > 0.5)))}


def _calibration(p, y_over, bins=10):
    edges = np.linspace(0, 1, bins + 1)
    idx = np.clip(np.digitize(p, edges) - 1, 0, bins - 1)
    return [{"bin": f"{edges[b]:.1f}-{edges[b + 1]:.1f}", "n": int((idx == b).sum()), "predicted": float(p[idx == b].mean()), "observed": float(y_over[idx == b].mean())}
            for b in range(bins) if (idx == b).sum() >= 20]


def fit(df: pd.DataFrame, out_dir: str | Path, target: str = "target", seed: int = 7) -> dict:
    df = df.sort_values("game_date").reset_index(drop=True)
    n = len(df)
    if n < 300:
        raise ValueError(f"need at least 300 rows to train, got {n}")
    train_end, valid_end = int(n * 0.70), int(n * 0.85)
    train, valid, test = df.iloc[:train_end], df.iloc[train_end:valid_end], df.iloc[valid_end:]

    # Pseudo-Huber: points are heavy-tailed (a 40-point night should not drag the fit); it held up far better than squared
    # error once the data moved from the regular season into the playoffs and a new season.
    model = xgb.XGBRegressor(n_estimators=1500, learning_rate=0.02, max_depth=3, subsample=0.8, colsample_bytree=0.8, min_child_weight=30,
                             reg_lambda=5.0, objective="reg:pseudohubererror", early_stopping_rounds=60, tree_method="hist", random_state=seed)
    model.fit(train[FEATURES], train[target], eval_set=[(valid[FEATURES], valid[target])], verbose=False)

    # spread of the error depends on the level (a 30-point scorer is noisier than a 6-point one): std per prediction bin
    valid_pred = model.predict(valid[FEATURES])
    edges = np.unique(np.quantile(valid_pred, np.linspace(0, 1, N_STD_BINS + 1)[1:-1]))
    resid = valid[target].to_numpy() - valid_pred
    bins = np.searchsorted(edges, valid_pred)
    stds = [float(max(np.std(resid[bins == b]), 1.0)) if (bins == b).sum() > 10 else float(np.std(resid)) for b in range(len(edges) + 1)]

    test_pred = model.predict(test[FEATURES])
    test_std = np.array([stds[int(np.searchsorted(edges, m))] for m in test_pred])
    y = test[target].to_numpy()
    lines = _proxy_lines(test)
    y_over = (y > lines).astype(float)
    base_rate = float(((train[target].to_numpy() > _proxy_lines(train)).astype(float)).mean())
    p_model = _p_over(test_pred, test_std, lines)
    p_base = _p_over(test["mean_l10"].to_numpy(), np.maximum(test["std_l10"].fillna(5.0).to_numpy(), 1.0), lines)

    metrics = {
        "rows": {"train": len(train), "valid": len(valid), "test": len(test)},
        "mae": {"model": float(np.mean(np.abs(y - test_pred))), "l10_mean": float(np.mean(np.abs(y - test["mean_l10"]))),
                "season_mean": float(np.mean(np.abs(y - test["mean_season"].fillna(test["mean_l10"])))),
                "blend_l10_season": float(np.mean(np.abs(y - (0.5 * test["mean_l10"] + 0.5 * test["mean_season"].fillna(test["mean_l10"])))))},
        "valid_mae": {"model": float(np.mean(np.abs(valid[target] - valid_pred))), "l10_mean": float(np.mean(np.abs(valid[target] - valid["mean_l10"])))},
        "over_vs_proxy_line": {"model": _scores(p_model, y_over), "baseline_l10_normal": _scores(p_base, y_over), "coin_flip": _scores(np.full_like(p_model, 0.5), y_over),
                               "train_base_rate": _scores(np.full_like(p_model, base_rate), y_over)},
        "calibration": _calibration(p_model, y_over),
        "test_period": [str(test["game_date"].min()), str(test["game_date"].max())],
        "note": "Evaluated on lines synthesised from the L10 mean, because historical betting lines are not stored.",
    }
    version = datetime.now(timezone.utc).strftime("%Y%m%d") + "-" + hashlib.sha1(f"{n}{FEATURES}{seed}".encode()).hexdigest()[:6]
    meta = {"version": version, "features": FEATURES, "std_edges": [float(e) for e in edges], "stds": stds, "metrics": metrics,
            "trained_at": datetime.now(timezone.utc).isoformat(), "best_iteration": int(model.best_iteration)}
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    model.save_model(str(out / "model.json"))
    (out / "meta.json").write_text(json.dumps(meta, indent=2))
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", default="models/points")
    args = ap.parse_args()
    meta = fit(pd.read_csv(args.data), args.out)
    m = meta["metrics"]
    print(f"model {meta['version']}  rows {m['rows']}  test {m['test_period'][0]} .. {m['test_period'][1]}")
    print("test  MAE  model %.3f | L10 mean %.3f | season mean %.3f | 50/50 blend %.3f" % (m["mae"]["model"], m["mae"]["l10_mean"], m["mae"]["season_mean"], m["mae"]["blend_l10_season"]))
    print("valid MAE  model %.3f | L10 mean %.3f" % (m["valid_mae"]["model"], m["valid_mae"]["l10_mean"]))
    for k, v in m["over_vs_proxy_line"].items():
        print(f"{k:22s} brier {v['brier']:.4f}  log-loss {v['log_loss']:.4f}  accuracy {v['accuracy']:.3f}")
    print("calibration (predicted -> observed):", ", ".join(f"{c['predicted']:.2f}->{c['observed']:.2f} (n={c['n']})" for c in m["calibration"]))


if __name__ == "__main__":
    main()
