#!/usr/bin/env python3
"""Save a docked AMCL pose and safely restore it on later boots."""
import hashlib
import json
import math
import os
from pathlib import Path

from control_msgs.msg import DynamicJointState
from geometry_msgs.msg import PoseWithCovarianceStamped
import rclpy
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node


def map_version(yaml_path):
    import yaml
    yaml_path = Path(yaml_path)
    yaml_bytes = yaml_path.read_bytes()
    metadata = yaml.safe_load(yaml_bytes)
    image_bytes = (yaml_path.parent / str(metadata['image'])).read_bytes()
    return hashlib.sha256(yaml_bytes + b'\0' + image_bytes).hexdigest()


def pose_payload(message, version):
    q = message.pose.pose.orientation
    yaw = math.atan2(2.0 * (q.w * q.z + q.x * q.y),
                     1.0 - 2.0 * (q.y ** 2 + q.z ** 2))
    return {'frame_id': 'map', 'map_version': version,
            'x': float(message.pose.pose.position.x),
            'y': float(message.pose.pose.position.y), 'yaw': float(yaw)}


def valid_payload(payload, version):
    if not isinstance(payload, dict):
        return False
    if payload.get('frame_id') != 'map' or payload.get('map_version') != version:
        return False
    return all(isinstance(payload.get(key), (int, float)) and
               not isinstance(payload.get(key), bool) and
               math.isfinite(float(payload[key])) for key in ('x', 'y', 'yaw'))


def save_pose_file(path, x, y, yaw, version):
    """Atomically persist a map-version-bound dock pose."""
    path = Path(path).expanduser()
    payload = {'frame_id': 'map', 'map_version': version,
               'x': float(x), 'y': float(y), 'yaw': float(yaw)}
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(payload, indent=2) + '\n',
                         encoding='utf-8')
    os.replace(temporary, path)
    return payload


class DockPoseInitializer(Node):
    def __init__(self):
        super().__init__('dock_pose_initializer')
        self.declare_parameter(
            'pose_file', '/home/carelink/.config/carelink/dock_pose.json')
        self.declare_parameter(
            'map_yaml_path', '/home/carelink/robot_ws/src/articubot_one/maps/'
            'new_map02.yaml')
        self.pose_file = Path(str(self.get_parameter('pose_file').value)).expanduser()
        self.version = map_version(self.get_parameter('map_yaml_path').value)
        self.saved_pose = self._load_pose()
        self.docked = None
        self.restore_count = 0
        self.calibrated = self.saved_pose is not None
        self.publisher = self.create_publisher(
            PoseWithCovarianceStamped, '/initialpose', 10)
        self.create_subscription(DynamicJointState, '/dynamic_joint_states',
                                 self.status_callback, 10)
        self.create_subscription(PoseWithCovarianceStamped, '/amcl_pose',
                                 self.pose_callback, 10)
        self.create_timer(1.0, self.restore)
        if self.calibrated:
            self.get_logger().info('Dock pose loaded; restoring startup pose')
        else:
            self.get_logger().warning(
                'No dock pose yet. Set the initial pose once while dock_state=1; '
                'it will be saved for future boots.')

    def _load_pose(self):
        if not self.pose_file.is_file():
            return None
        try:
            payload = json.loads(self.pose_file.read_text(encoding='utf-8'))
        except (OSError, ValueError) as error:
            self.get_logger().error(f'Cannot read dock pose: {error}')
            return None
        if not valid_payload(payload, self.version):
            self.get_logger().error(
                'Dock pose is invalid or belongs to another map; restore disabled')
            return None
        return payload

    def status_callback(self, message):
        for index, joint_name in enumerate(message.joint_names):
            if joint_name != 'carelink_status' or index >= len(message.interface_values):
                continue
            values = message.interface_values[index]
            for value_index, name in enumerate(values.interface_names):
                if name == 'dock_state' and value_index < len(values.values):
                    previous = self.docked
                    self.docked = values.values[value_index] >= 0.5
                    if previous is None or previous != self.docked:
                        self.get_logger().info(f'dock_state={int(self.docked)}')
                    return

    def pose_callback(self, message):
        if not self.docked or self.calibrated:
            return
        payload = pose_payload(message, self.version)
        try:
            save_pose_file(self.pose_file, payload['x'], payload['y'],
                           payload['yaw'], self.version)
        except OSError as error:
            self.get_logger().error(f'Cannot save dock pose: {error}')
            return
        self.saved_pose = payload
        self.calibrated = True
        self.get_logger().info(
            f"Dock pose saved: x={payload['x']:.3f}, y={payload['y']:.3f}, "
            f"yaw={payload['yaw']:.3f}")

    def restore(self):
        if self.saved_pose is None or self.restore_count >= 3:
            return
        pose = self.saved_pose
        message = PoseWithCovarianceStamped()
        message.header.frame_id = 'map'
        # Keep the zero timestamp so AMCL uses the latest available odom TF.
        # Stamping this with "now" can fall outside the TF buffer.
        message.pose.pose.position.x = float(pose['x'])
        message.pose.pose.position.y = float(pose['y'])
        message.pose.pose.orientation.z = math.sin(float(pose['yaw']) / 2.0)
        message.pose.pose.orientation.w = math.cos(float(pose['yaw']) / 2.0)
        message.pose.covariance[0] = message.pose.covariance[7] = 0.0025
        message.pose.covariance[35] = 0.01
        self.publisher.publish(message)
        self.restore_count += 1
        self.get_logger().info(
            f'Published dock initial pose ({self.restore_count}/3)')


def main(args=None):
    rclpy.init(args=args)
    node = None
    try:
        node = DockPoseInitializer()
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        if node is not None:
            node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
