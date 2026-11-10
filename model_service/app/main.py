from __future__ import annotations

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import model
from .probability import decided, over_under_push

MODEL_DIR = Path(os.environ.get("MODEL_DIR", Path(__file__).resolve().parent.parent / "models" / "points"))
MAX_ROWS = 500


class Row(BaseModel):
    id: str
    line: float
    features: dict[str, float | None]


class PredictRequest(BaseModel):
    rows: list[Row] = Field(max_length=MAX_ROWS)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.bundle = model.load(MODEL_DIR) if (MODEL_DIR / "model.json").exists() else None
    yield


app = FastAPI(title="Propscope model service", lifespan=lifespan)


@app.get("/health")
def health():
    bundle = app.state.bundle
    return {"status": "ok" if bundle else "no_model", "model_loaded": bundle is not None, "model_version": bundle.version if bundle else None}


@app.get("/model")
def describe():
    bundle = app.state.bundle
    if bundle is None:
        raise HTTPException(503, "no model loaded")
    return {"version": bundle.version, "features": bundle.features, "metrics": bundle.meta.get("metrics", {}), "trained_at": bundle.meta.get("trained_at")}


@app.post("/predict")
def predict(req: PredictRequest):
    bundle = app.state.bundle
    if bundle is None:
        raise HTTPException(503, "no model loaded")
    wanted = set(bundle.features)
    for row in req.rows:
        missing = wanted - set(row.features)
        if missing:
            raise HTTPException(422, f"row {row.id}: missing features {sorted(missing)}")

    out = []
    for row, (projection, std) in zip(req.rows, bundle.predict([r.features for r in req.rows])):
        probs = decided(over_under_push(projection, std, row.line))
        out.append({"id": row.id, "projection": round(projection, 3), "std": round(std, 3),
                    "p_over": round(probs["p_over"], 5), "p_under": round(probs["p_under"], 5), "p_push": round(probs["p_push"], 5)})
    return {"model_version": bundle.version, "predictions": out}
