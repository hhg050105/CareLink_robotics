#!/usr/bin/env python3
"""Upload the live ROS occupancy map to Firestore as a Base64 PNG."""

import base64
import hashlib
import io
from pathlib import Path
from typing import Optional, Tuple

import rclpy
from nav_msgs.msg import OccupancyGrid
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node


FIRESTORE_SAFE_IMAGE_BYTES = 700_000


def occupancy_grid_to_png(
        width: int, height: int, values) -> Tuple[bytes, int, int]:
    """Convert ROS bottom-left occupancy rows to a top-left grayscale PNG."""
    if width <= 0 or height <= 0:
        raise ValueError('map width and height must be greater than zero')
    if len(values) != width * height:
        raise ValueError('occupancy data size does not match map dimensions')

    from PIL import Image

    pixels = []
    for value in values:
        if value < 0:
            pixels.append(205)
        else:
            bounded = max(0, min(100, int(value)))
            pixels.append(round(254 * (100 - bounded) / 100))

    image = Image.new('L', (width, height))
    image.putdata(pixels)
    image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    buffer = io.BytesIO()
    image.save(buffer, format='PNG', optimize=True)
    return buffer.getvalue(), width, height


class FirebaseLiveMapNode(Node):
    """Periodically upload changed /map data while SLAM is running."""

    def __init__(self) -> None:
        super().__init__('firebase_live_map')
        self.declare_parameter(
            'credential_path',
            '/home/carelink/camera_stack/secrets/firebase-service-account.json')
        self.declare_parameter('map_document_path', 'robot_maps/main')
        self.declare_parameter('upload_interval_sec', 5.0)

        interval = float(self.get_parameter('upload_interval_sec').value)
        if interval < 2.0:
            raise ValueError('upload_interval_sec must be at least 2 seconds')

        self.latest_map: Optional[OccupancyGrid] = None
        self.last_uploaded_hash: Optional[str] = None
        self.document, self.firestore = self._connect_firestore()
        self.create_subscription(OccupancyGrid, '/map', self.map_callback, 1)
        self.create_timer(interval, self.upload_latest_map)
        self.get_logger().info(
            f'Watching /map; Firebase upload interval={interval:.1f}s')

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

        document_path = str(
            self.get_parameter('map_document_path').value).strip('/')
        return firestore.client().document(document_path), firestore

    def map_callback(self, message: OccupancyGrid) -> None:
        self.latest_map = message

    def upload_latest_map(self) -> None:
        message = self.latest_map
        if message is None:
            return

        try:
            png, width, height = occupancy_grid_to_png(
                message.info.width, message.info.height, message.data)
            if len(png) > FIRESTORE_SAFE_IMAGE_BYTES:
                raise ValueError(
                    f'PNG is too large for Firestore: {len(png)} bytes')

            image_hash = hashlib.sha256(png).hexdigest()
            if image_hash == self.last_uploaded_hash:
                return

            origin = message.info.origin
            payload = {
                'imageBase64': base64.b64encode(png).decode('ascii'),
                'imageMimeType': 'image/png',
                'width': width,
                'height': height,
                'resolution': float(message.info.resolution),
                'origin': [
                    float(origin.position.x),
                    float(origin.position.y),
                    self._yaw_from_quaternion(
                        origin.orientation.x,
                        origin.orientation.y,
                        origin.orientation.z,
                        origin.orientation.w),
                ],
                'frameId': message.header.frame_id or 'map',
                'source': 'live_slam',
                'imageSha256': image_hash,
                'updatedAt': self.firestore.SERVER_TIMESTAMP,
            }
            self.document.set(payload, merge=True, timeout=10.0)
            self.last_uploaded_hash = image_hash
            self.get_logger().info(
                f'Firebase live map: {width}x{height}, PNG={len(png)} bytes')
        except Exception as error:
            self.get_logger().error(f'Firebase live map upload failed: {error}')

    @staticmethod
    def _yaw_from_quaternion(x: float, y: float, z: float, w: float) -> float:
        import math
        return math.atan2(
            2.0 * (w * z + x * y),
            1.0 - 2.0 * (y * y + z * z))


def main(args=None) -> None:
    rclpy.init(args=args)
    node = None
    try:
        node = FirebaseLiveMapNode()
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
