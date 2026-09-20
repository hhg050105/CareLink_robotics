#!/usr/bin/env python3
"""Bridge a Firestore patrol command to the existing RViz clicked-point flow."""

import base64
import io
import math
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

import rclpy
from rclpy.executors import ExternalShutdownException
from geometry_msgs.msg import PointStamped
from rclpy.node import Node


def parse_points(data: Dict[str, Any]) -> List[Tuple[float, float]]:
    """Return exactly three finite x/y map coordinates."""
    raw_points = data.get('points')
    if not isinstance(raw_points, list) or len(raw_points) != 3:
        raise ValueError('points must contain exactly three items')

    points = []
    for index, raw_point in enumerate(raw_points, start=1):
        if not isinstance(raw_point, dict):
            raise ValueError(f'P{index} must be an object')
        x = raw_point.get('x')
        y = raw_point.get('y')
        if (isinstance(x, bool) or isinstance(y, bool) or
                not isinstance(x, (int, float)) or
                not isinstance(y, (int, float))):
            raise ValueError(f'P{index} x and y must be numbers')
        x = float(x)
        y = float(y)
        if not math.isfinite(x) or not math.isfinite(y):
            raise ValueError(f'P{index} x and y must be finite')
        points.append((x, y))
    return points


def point_is_in_map(
        point: Tuple[float, float],
        origin: Sequence[float],
        resolution: float,
        width: int,
        height: int) -> bool:
    """Check a world point against the possibly rotated map image bounds."""
    dx = point[0] - float(origin[0])
    dy = point[1] - float(origin[1])
    yaw = float(origin[2])
    local_x = math.cos(yaw) * dx + math.sin(yaw) * dy
    local_y = -math.sin(yaw) * dx + math.cos(yaw) * dy
    return 0.0 <= local_x < width * resolution and 0.0 <= local_y < height * resolution


class FirebasePatrolBridge(Node):
    """Upload the map and relay accepted Firestore commands to /clicked_point."""

    def __init__(self) -> None:
        super().__init__('firebase_patrol_bridge')
        self.declare_parameter(
            'credential_path',
            '/home/carelink/camera_stack/secrets/firebase-service-account.json')
        self.declare_parameter(
            'map_yaml_path',
            '/home/carelink/robot_ws/src/articubot_one/maps/'
            'new_map02.yaml')
        self.declare_parameter('map_document_path', 'robot_maps/main')
        self.declare_parameter('command_document_path', 'robot_commands/patrol')
        self.declare_parameter('poll_interval_sec', 1.0)

        interval = float(self.get_parameter('poll_interval_sec').value)
        if interval <= 0:
            raise ValueError('poll_interval_sec must be greater than zero')

        self.publisher = self.create_publisher(PointStamped, '/clicked_point', 10)
        self.last_command_id = None
        self.db, self.firestore = self._connect_firestore()
        self.map_info = self._load_and_upload_map()
        command_path = str(
            self.get_parameter('command_document_path').value).strip('/')
        self.command_document = self.db.document(command_path)
        self.create_timer(interval, self.poll_command)
        self.get_logger().info(f'Watching Firebase command: {command_path}')

    def _connect_firestore(self):
        import firebase_admin
        from firebase_admin import credentials, firestore

        credential_path = Path(
            str(self.get_parameter('credential_path').value)).expanduser()
        if not credential_path.is_file():
            raise FileNotFoundError(
                f'Firebase credential not found: {credential_path}')
        if not firebase_admin._apps:
            firebase_admin.initialize_app(
                credentials.Certificate(str(credential_path)))
        return firestore.client(), firestore

    def _load_and_upload_map(self) -> Dict[str, Any]:
        import yaml
        from PIL import Image

        yaml_path = Path(
            str(self.get_parameter('map_yaml_path').value)).expanduser()
        with yaml_path.open('r', encoding='utf-8') as stream:
            metadata = yaml.safe_load(stream)

        image_path = yaml_path.parent / str(metadata['image'])
        resolution = float(metadata['resolution'])
        origin = [float(value) for value in metadata['origin']]
        with Image.open(image_path) as image:
            grayscale = image.convert('L')
            width, height = grayscale.size
            buffer = io.BytesIO()
            grayscale.save(buffer, format='PNG')

        payload = {
            'imageBase64': base64.b64encode(buffer.getvalue()).decode('ascii'),
            'imageMimeType': 'image/png',
            'width': width,
            'height': height,
            'resolution': resolution,
            'origin': origin,
            'frameId': 'map',
            'updatedAt': self.firestore.SERVER_TIMESTAMP,
        }
        map_path = str(
            self.get_parameter('map_document_path').value).strip('/')
        self.db.document(map_path).set(payload, merge=True, timeout=10.0)
        self.get_logger().info(
            f'Firebase map uploaded: {map_path} ({width}x{height})')
        return {
            'width': width,
            'height': height,
            'resolution': resolution,
            'origin': origin,
        }

    def poll_command(self) -> None:
        try:
            snapshot = self.command_document.get(timeout=5.0)
            if not snapshot.exists:
                return
            data = snapshot.to_dict() or {}
            command_id = data.get('commandId')
            command = str(data.get('command', '')).strip().upper()
            status = str(data.get('status', '')).strip().upper()
            if (command != 'START' or status != 'REQUESTED' or
                    not isinstance(command_id, str)):
                return
            if not command_id.strip() or command_id == self.last_command_id:
                return
            if self.publisher.get_subscription_count() == 0:
                self.get_logger().warn(
                    'Patrol command is waiting: patrol_dock is not subscribed')
                return

            points = parse_points(data)
            for index, point in enumerate(points, start=1):
                if not point_is_in_map(
                        point,
                        self.map_info['origin'],
                        self.map_info['resolution'],
                        self.map_info['width'],
                        self.map_info['height']):
                    raise ValueError(f'P{index} is outside the map')

            for x, y in points:
                message = PointStamped()
                message.header.stamp = self.get_clock().now().to_msg()
                message.header.frame_id = 'map'
                message.point.x = x
                message.point.y = y
                self.publisher.publish(message)

            self.last_command_id = command_id
            self.command_document.set({
                'status': 'ACCEPTED',
                'acceptedAt': self.firestore.SERVER_TIMESTAMP,
                'error': self.firestore.DELETE_FIELD,
            }, merge=True, timeout=5.0)
            self.get_logger().info(
                f'Patrol command accepted: {command_id}, P1 -> P2 -> P3')
        except ValueError as error:
            self.command_document.set({
                'status': 'REJECTED',
                'error': str(error),
                'rejectedAt': self.firestore.SERVER_TIMESTAMP,
            }, merge=True, timeout=5.0)
            self.get_logger().error(f'Patrol command rejected: {error}')
        except Exception as error:
            self.get_logger().error(f'Firebase patrol poll failed: {error}')


def main(args=None) -> None:
    rclpy.init(args=args)
    node = None
    try:
        node = FirebasePatrolBridge()
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    except ExternalShutdownException:
        pass
    finally:
        if node is not None:
            node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
