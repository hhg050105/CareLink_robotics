import math

from carelink_patrol.firebase_nav_bridge import (
    app_yaw_to_map_yaw, build_round_trip, normalize_yaw, parse_goal,
    parse_patrol, pixel_is_free, validate_goal_cell, world_to_cell)
import pytest


def map_info(pixels=None):
    return {
        'width': 4, 'height': 3, 'resolution': 0.5,
        'origin': [-1.0, -0.5, 0.0], 'negate': 0,
        'free_thresh': 0.196,
        'pixels': pixels or [254] * 12,
    }


def test_parse_goal_accepts_finite_numbers():
    assert parse_goal({'commandId': ' goal-1 ', 'x': 1, 'y': -0.25,
                       'yaw': math.pi}) == ('goal-1', 1.0, -0.25, math.pi)


@pytest.mark.parametrize('field,value', [
    ('x', True), ('y', '1'), ('yaw', math.inf),
])
def test_parse_goal_rejects_invalid_coordinates(field, value):
    data = {'commandId': 'goal-1', 'x': 0, 'y': 0, 'yaw': 0}
    data[field] = value
    with pytest.raises(ValueError):
        parse_goal(data)


def test_parse_patrol_accepts_three_points_and_defaults_yaw():
    command_id, points = parse_patrol({
        'commandId': ' patrol-1 ',
        'points': [
            {'x': 0, 'y': 1},
            {'x': 2.5, 'y': -1, 'yaw': math.pi},
            {'x': -0.5, 'y': 0.25},
        ],
    })
    assert command_id == 'patrol-1'
    assert points == [(0.0, 1.0, 0.0), (2.5, -1.0, math.pi),
                      (-0.5, 0.25, 0.0)]


def test_normalize_yaw_wraps_angles():
    assert normalize_yaw(math.pi / 2) == pytest.approx(math.pi / 2)
    assert normalize_yaw(3 * math.pi / 2) == pytest.approx(-math.pi / 2)


def test_app_yaw_to_map_yaw_uses_ros_map_convention():
    assert app_yaw_to_map_yaw(math.pi / 2) == pytest.approx(math.pi / 2)
    assert app_yaw_to_map_yaw(-math.pi / 2) == pytest.approx(-math.pi / 2)
    assert app_yaw_to_map_yaw(3 * math.pi) == pytest.approx(-math.pi)


def test_build_round_trip_reverses_points_and_headings():
    route = build_round_trip([
        (0.0, 0.0, 0.25),
        (1.0, 0.0, 0.5),
        (1.0, 1.0, 0.75),
    ])
    assert [(x, y) for x, y, _yaw in route] == [
        (0.0, 0.0), (1.0, 0.0), (1.0, 1.0),
        (1.0, 0.0), (0.0, 0.0),
    ]
    assert [yaw for _x, _y, yaw in route] == pytest.approx(
        [0.0, math.pi / 2, -math.pi / 2, math.pi, 0.25])


def test_parse_patrol_rejects_wrong_count_and_bad_coordinate():
    with pytest.raises(ValueError, match='exactly three'):
        parse_patrol({'commandId': 'patrol-1', 'points': []})
    with pytest.raises(ValueError, match='P2 x'):
        parse_patrol({'commandId': 'patrol-1', 'points': [
            {'x': 0, 'y': 0}, {'x': 'bad', 'y': 0}, {'x': 0, 'y': 0}]})


def test_world_to_cell_flips_pgm_row_axis():
    assert world_to_cell(-0.75, -0.25, map_info()) == (0, 2)
    assert world_to_cell(0.75, 0.75, map_info()) == (3, 0)


def test_world_to_cell_rejects_upper_exclusive_edge():
    with pytest.raises(ValueError, match='outside'):
        world_to_cell(1.0, 0.0, map_info())


def test_pixel_threshold_and_goal_validation():
    assert pixel_is_free(254, 0, 0.196)
    assert not pixel_is_free(205, 0, 0.196)
    pixels = [254] * 12
    pixels[3] = 0
    with pytest.raises(ValueError, match='occupied or unknown'):
        validate_goal_cell(0.75, 0.75, map_info(pixels))


def test_rotated_origin_conversion():
    info = map_info()
    info['origin'] = [0.0, 0.0, math.pi / 2]
    assert world_to_cell(-0.25, 0.25, info) == (0, 2)
