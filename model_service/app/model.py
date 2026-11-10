from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import xgboost as xgb


@dataclass
class Bundle:
    booster: xgb.XGBRegressor
    meta: dict

    @property
    def version(self) -> str:
        return self.meta["version"]

    @property
    def features(self) -> list[str]:
        return self.meta["features"]

    def predict(self, rows: list[dict[str, float | None]]) -> list[tuple[float, float]]:
        """Returns (projection, std) per row. Missing values are passed to XGBoost as NaN."""
        x = np.array([[np.nan if r.get(f) is None else float(r[f]) for f in self.features] for r in rows], dtype=float)
        means = self.booster.predict(x)
        return [(float(m), self.std_for(float(m))) for m in means]

    def std_for(self, mean: float) -> float:
        edges, stds = self.meta["std_edges"], self.meta["stds"]
        return float(stds[int(np.searchsorted(edges, mean))])


def load(model_dir: str | Path) -> Bundle:
    model_dir = Path(model_dir)
    meta = json.loads((model_dir / "meta.json").read_text())
    booster = xgb.XGBRegressor()
    booster.load_model(str(model_dir / "model.json"))
    return Bundle(booster=booster, meta=meta)
