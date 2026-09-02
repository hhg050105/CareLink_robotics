import math

import pytest

from carelink_patrol.firebase_patrol_bridge import parse_points, point_is_in_map


def test_parse_points_accepts_three_coordinates():
    assert parse_points({
        'points': [
            {'x': 1, 'y': 2.5},
            {'x': -1.0, 'y': 0},
            {'x': 3.25, 'y': -4},
        ],
    }) == [(1.0, 2.5), (-1.0, 0.0), (3.25, -4.0)]


@pytest.mark.parametrize('points', [[], [{'x': 1, 'y': 2}], [1, 2, 3]])
def test_parse_points_rejects_invalid_count_or_shape(points):
    with pytest.raises(ValueError):
        parse_points({'points': points})


def test_parse_points_rejects_non_finite_values():
    with pytest.raises(ValueError):
        parse_points({
            'points': [
                {'x': math.nan, 'y': 0},
                {'x': 1, 'y': 1},
                {'x': 2, 'y': 2},
            ],
        })


def test_point_is_in_unrotated_map():
    origin = [-4.0, -3.0, 0.0]
    assert point_is_in_map((-3.0, -2.0), origin, 0.05, 100, 100)
    assert not point_is_in_map((2.0, -2.0), origin, 0.05, 100, 100)
