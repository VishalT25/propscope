import pytest

from app.probability import MIN_STD, decided, over_under_push


def test_half_lines_never_push_and_sum_to_one():
    p = over_under_push(24.0, 6.0, 24.5)
    assert p["p_push"] == 0.0
    assert p["p_over"] + p["p_under"] == pytest.approx(1.0)
    assert p["p_over"] < 0.5  # mean is below the line


def test_whole_lines_can_push():
    p = over_under_push(24.0, 6.0, 24.0)
    assert 0.04 < p["p_push"] < 0.12
    assert p["p_over"] + p["p_under"] + p["p_push"] == pytest.approx(1.0)


def test_symmetric_when_mean_is_the_line_on_a_half_point():
    p = over_under_push(24.5, 6.0, 24.5)
    assert p["p_over"] == pytest.approx(0.5)


def test_higher_projection_means_higher_over_probability():
    lo = over_under_push(20.0, 6.0, 22.5)["p_over"]
    hi = over_under_push(26.0, 6.0, 22.5)["p_over"]
    assert hi > lo


def test_wider_spread_pulls_probability_toward_a_coin_flip():
    narrow = over_under_push(30.0, 3.0, 24.5)["p_over"]
    wide = over_under_push(30.0, 12.0, 24.5)["p_over"]
    assert narrow > wide > 0.5


def test_tiny_or_zero_std_is_floored_not_divided_by_zero():
    p = over_under_push(10.0, 0.0, 9.5)
    assert 0.0 <= p["p_over"] <= 1.0
    assert over_under_push(10.0, 0.0, 9.5) == over_under_push(10.0, MIN_STD, 9.5)


def test_decided_renormalises_without_the_push_and_keeps_it_reported():
    d = decided(over_under_push(24.0, 6.0, 24.0))
    assert d["p_over"] + d["p_under"] == pytest.approx(1.0)
    assert d["p_push"] > 0


def test_decided_handles_a_degenerate_distribution():
    assert decided({"p_over": 0.0, "p_under": 0.0, "p_push": 1.0})["p_over"] == 0.5
