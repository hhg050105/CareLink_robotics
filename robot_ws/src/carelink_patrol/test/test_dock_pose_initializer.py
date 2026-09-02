import math
from pathlib import Path

from geometry_msgs.msg import PoseWithCovarianceStamped
import pytest

from carelink_patrol.dock_pose_initializer import (
    map_version, pose_payload, save_pose_file, valid_payload)


def test_map_version_includes_image(tmp_path: Path):
    image = tmp_path / 'map.pgm'
    image.write_bytes(b'P5\n1 1\n255\n\xff')
    yaml_file = tmp_path / 'map.yaml'
    yaml_file.write_text('image: map.pgm\n', encoding='utf-8')
    first = map_version(yaml_file)
    image.write_bytes(b'P5\n1 1\n255\n\x00')
    assert map_version(yaml_file) != first


def test_pose_payload_and_validation():
    message = PoseWithCovarianceStamped()
    message.pose.pose.position.x = 1.25
    message.pose.pose.position.y = -0.5
    message.pose.pose.orientation.z = math.sin(0.3)
    message.pose.pose.orientation.w = math.cos(0.3)
    payload = pose_payload(message, 'map-version')
    assert payload['yaw'] == pytest.approx(0.6)
    assert valid_payload(payload, 'map-version')
    assert not valid_payload(payload, 'different-map')


def test_payload_rejects_non_finite_pose():
    payload = {'frame_id': 'map', 'map_version': 'v1',
               'x': math.nan, 'y': 0.0, 'yaw': 0.0}
    assert not valid_payload(payload, 'v1')


def test_save_pose_file_is_valid_and_replaces_existing_file(tmp_path: Path):
    pose_file = tmp_path / 'carelink' / 'dock_pose.json'
    first = save_pose_file(pose_file, 1.0, 2.0, 0.5, 'v1')
    second = save_pose_file(pose_file, -1.0, 0.25, -0.5, 'v1')

    assert valid_payload(first, 'v1')
    assert valid_payload(second, 'v1')
    assert '"x": -1.0' in pose_file.read_text(encoding='utf-8')
