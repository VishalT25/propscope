"""Turn a predicted stat distribution into over/under/push probabilities for a line.

Box-score stats are integers, so a line of 24.5 can never push, while a whole-number line (24.0) pushes when the stat
lands on 24. We model the stat as Normal(mean, std) with a continuity correction: "X >= 25" is "X > 24.5".
"""
from __future__ import annotations

from math import erf, sqrt

MIN_STD = 1.0


def _cdf(x: float, mean: float, std: float) -> float:
    return 0.5 * (1.0 + erf((x - mean) / (std * sqrt(2.0))))


def over_under_push(mean: float, std: float, line: float) -> dict[str, float]:
    std = max(float(std), MIN_STD)
    if float(line).is_integer():
        p_under = _cdf(line - 0.5, mean, std)            # X <= line - 1
        p_push = _cdf(line + 0.5, mean, std) - p_under   # X == line
        p_over = 1.0 - p_under - p_push                  # X >= line + 1
    else:
        p_under = _cdf(line, mean, std)
        p_push = 0.0
        p_over = 1.0 - p_under
    return {"p_over": p_over, "p_under": p_under, "p_push": p_push}


def decided(probs: dict[str, float]) -> dict[str, float]:
    """Probability each side wins given the bet is not a push (matches how hit rates exclude pushes)."""
    total = probs["p_over"] + probs["p_under"]
    if total <= 0:
        return {"p_over": 0.5, "p_under": 0.5, "p_push": probs["p_push"]}
    return {"p_over": probs["p_over"] / total, "p_under": probs["p_under"] / total, "p_push": probs["p_push"]}
