import numpy as np
import pandas as pd
import pytest
from fastapi.testclient import TestClient

from app.features import FEATURES
from train import fit


def synthetic_frame(n=1500, seed=3):
    rng = np.random.default_rng(seed)
    df = pd.DataFrame({f: rng.normal(10, 3, n) for f in FEATURES})
    df["is_home"] = rng.integers(0, 2, n)
    df["back_to_back"] = rng.integers(0, 2, n)
    df["rest_days"] = rng.integers(1, 5, n)
    df["game_date"] = pd.date_range("2025-10-20", periods=n, freq="h").astype(str)
    df["target"] = np.clip(0.6 * df["mean_l10"] + 0.3 * df["mean_l5"] + 1.5 * df["is_home"] + rng.normal(0, 3, n), 0, None).round()
    return df


@pytest.fixture(scope="module")
def model_dir(tmp_path_factory):
    out = tmp_path_factory.mktemp("model")
    fit(synthetic_frame(), out)
    return out


@pytest.fixture()
def client(model_dir, monkeypatch):
    monkeypatch.setenv("MODEL_DIR", str(model_dir))
    import importlib

    import app.main as main
    importlib.reload(main)
    with TestClient(main.app) as c:
        yield c


def row(id="a", line=10.5, **over):
    feats = {f: 10.0 for f in FEATURES}
    feats.update(over)
    return {"id": id, "line": line, "features": feats}


def test_health_reports_the_loaded_model(client):
    body = client.get("/health").json()
    assert body["status"] == "ok" and body["model_loaded"] and body["model_version"]


def test_predicts_probabilities_that_make_sense(client):
    r = client.post("/predict", json={"rows": [row("low", 20.5, mean_l10=5.0, mean_l5=5.0), row("high", 20.5, mean_l10=22.0, mean_l5=22.0)]}).json()
    low, high = r["predictions"]
    assert high["projection"] > low["projection"]
    assert high["p_over"] > low["p_over"]
    for p in (low, high):
        assert p["p_over"] + p["p_under"] == pytest.approx(1.0, abs=1e-4)
    assert r["model_version"]


def test_whole_number_lines_report_a_push_probability(client):
    p = client.post("/predict", json={"rows": [row("w", 10.0)]}).json()["predictions"][0]
    assert p["p_push"] > 0
    assert client.post("/predict", json={"rows": [row("h", 10.5)]}).json()["predictions"][0]["p_push"] == 0


def test_missing_values_are_accepted(client):
    r = client.post("/predict", json={"rows": [row("n", 10.5, mean_season=None, std_l10=None)]})
    assert r.status_code == 200


def test_missing_features_are_rejected(client):
    bad = {"id": "x", "line": 10.5, "features": {"mean_l5": 1.0}}
    r = client.post("/predict", json={"rows": [bad]})
    assert r.status_code == 422 and "missing features" in r.json()["detail"]


def test_too_many_rows_are_rejected(client):
    assert client.post("/predict", json={"rows": [row(str(i)) for i in range(501)]}).status_code == 422


def test_without_a_model_the_service_says_so(tmp_path, monkeypatch):
    monkeypatch.setenv("MODEL_DIR", str(tmp_path))
    import importlib

    import app.main as main
    importlib.reload(main)
    with TestClient(main.app) as c:
        assert c.get("/health").json()["status"] == "no_model"
        assert c.post("/predict", json={"rows": [row()]}).status_code == 503
        assert c.get("/model").status_code == 503


def test_training_reports_metrics_against_baselines(model_dir):
    import json
    meta = json.loads((model_dir / "meta.json").read_text())
    m = meta["metrics"]
    assert m["mae"]["model"] < m["mae"]["season_mean"]
    assert {"model", "baseline_l10_normal", "coin_flip", "train_base_rate"} <= set(m["over_vs_proxy_line"])
    assert {"model", "l10_mean", "season_mean", "blend_l10_season"} <= set(m["mae"])
    assert meta["features"] == FEATURES


def test_training_refuses_tiny_datasets(tmp_path):
    with pytest.raises(ValueError, match="at least 300"):
        fit(synthetic_frame(100), tmp_path)
