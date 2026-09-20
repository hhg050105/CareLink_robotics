#!/usr/bin/env python3
"""Bridge Firestore goals and three-point patrols to Nav2."""

import math
from pathlib import Path
from typing import Any, Dict, List, Tuple

from ament_index_python.packages import get_package_share_directory
from action_msgs.msg import GoalStatus
from control_msgs.msg import DynamicJointState
from geometry_msgs.msg import PoseStamped, PoseWithCovarianceStamped
from nav2_msgs.action import BackUp, NavigateToPose
from nav2_msgs.srv import ManageLifecycleNodes
from builtin_interfaces.msg import Duration
import rclpy
from rclpy.action import ActionClient
from rclpy.executors import ExternalShutdownException
from rclpy.node import Node

from carelink_patrol.dock_pose_initializer import save_pose_file


def parse_goal(data: Dict[str, Any]) -> Tuple[str, float, float, float]:
    """Validate and return command id and a finite x/y/yaw goal."""
    command_id = data.get('commandId')
    if not isinstance(command_id, str) or not command_id.strip():
        raise ValueError('commandId must be a non-empty string')
    values = []
    for name in ('x', 'y', 'yaw'):
        value = data.get(name)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f'{name} must be a number')
        value = float(value)
        if not math.isfinite(value):
            raise ValueError(f'{name} must be finite')
        values.append(value)
    return command_id.strip(), values[0], values[1], values[2]


def parse_patrol(
        data: Dict[str, Any]) -> Tuple[str, List[Tuple[float, float, float]]]:
    """Validate and return exactly three finite x/y/yaw patrol points."""
    command_id = data.get('commandId')
    if not isinstance(command_id, str) or not command_id.strip():
        raise ValueError('commandId must be a non-empty string')
    raw_points = data.get('points')
    if not isinstance(raw_points, list) or len(raw_points) != 3:
        raise ValueError('points must contain exactly three items')

    points = []
    for index, raw_point in enumerate(raw_points, start=1):
        if not isinstance(raw_point, dict):
            raise ValueError(f'P{index} must be an object')
        values = []
        for name in ('x', 'y', 'yaw'):
            value = (raw_point.get(name, 0.0) if name == 'yaw'
                     else raw_point.get(name))
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError(f'P{index} {name} must be a number')
            value = float(value)
            if not math.isfinite(value):
                raise ValueError(f'P{index} {name} must be finite')
            values.append(value)
        points.append((values[0], values[1], values[2]))
    return command_id.strip(), points


def normalize_yaw(yaw: float) -> float:
    """Wrap an angle to the [-pi, pi) range."""
    return (yaw + math.pi) % (2.0 * math.pi) - math.pi


def app_yaw_to_map_yaw(app_yaw: float) -> float:
    """Normalize an app yaw that already uses the ROS map convention."""
    return normalize_yaw(app_yaw)


def build_round_trip(
        points: List[Tuple[float, float, float]]
        ) -> List[Tuple[float, float, float]]:
    """Expand P1/P2/P3 into P1/P2/P3/P2/P1 with travel headings."""
    if len(points) != 3:
        raise ValueError('round trip requires exactly three points')
    route_positions = [points[0], points[1], points[2], points[1], points[0]]
    route = []
    for index, (x, y, original_yaw) in enumerate(route_positions):
        if index + 1 < len(route_positions):
            next_x, next_y, _next_yaw = route_positions[index + 1]
            yaw = math.atan2(next_y - y, next_x - x)
        else:
            yaw = original_yaw
        route.append((x, y, yaw))
    return route


def world_to_cell(x: float, y: float, map_info: Dict[str, Any]) -> Tuple[int, int]:
    """Convert a map-frame point to a PGM cell whose row starts at the top."""
    origin = map_info['origin']
    dx, dy = x - origin[0], y - origin[1]
    yaw = origin[2]
    local_x = math.cos(yaw) * dx + math.sin(yaw) * dy
    local_y = -math.sin(yaw) * dx + math.cos(yaw) * dy
    col = math.floor(local_x / map_info['resolution'])
    row_from_bottom = math.floor(local_y / map_info['resolution'])
    row = map_info['height'] - 1 - row_from_bottom
    if not (0 <= col < map_info['width'] and 0 <= row < map_info['height']):
        raise ValueError('goal is outside the map')
    return col, row


def pixel_is_free(pixel: int, negate: int, free_thresh: float) -> bool:
    """Apply the map_server free-cell threshold to one grayscale pixel."""
    occupancy = pixel / 255.0 if negate else (255 - pixel) / 255.0
    return occupancy < free_thresh


def validate_goal_cell(x: float, y: float, map_info: Dict[str, Any]) -> Tuple[int, int]:
    """Require a goal to be inside the map and on a known free PGM cell."""
    col, row = world_to_cell(x, y, map_info)
    pixel = map_info['pixels'][row * map_info['width'] + col]
    if not pixel_is_free(pixel, map_info['negate'], map_info['free_thresh']):
        raise ValueError('goal cell is occupied or unknown')
    return col, row


class FirebaseNavBridge(Node):
    """Upload the fixed map and execute Firestore navigation commands."""

    def __init__(self) -> None:
        super().__init__('firebase_nav_bridge')
        self.declare_parameter(
            'credential_path',
            '/home/carelink/camera_stack/secrets/firebase-service-account.json')
        self.declare_parameter(
            'map_yaml_path',
            '/home/carelink/robot_ws/src/articubot_one/maps/new_map02.yaml')
        self.declare_parameter('map_document_path', 'robot_maps/main')
        self.declare_parameter('command_document_path', 'robot_commands/navigation')
        self.declare_parameter('patrol_behavior_tree', str(
            Path(get_package_share_directory('carelink_patrol')) / 'behavior_trees' / 'patrol.xml'))
        self.declare_parameter('poll_interval_sec', 1.0)
        self.declare_parameter('action_server_timeout_sec', 2.0)
        self.declare_parameter(
            'dock_pose_file', '/home/carelink/.config/carelink/dock_pose.json')

        interval = float(self.get_parameter('poll_interval_sec').value)
        if interval <= 0:
            raise ValueError('poll_interval_sec must be greater than zero')
        self.db, self.firestore = self._connect_firestore()
        command_path = str(self.get_parameter('command_document_path').value).strip('/')
        self.command_document = self.db.document(command_path)
        self.map_info = self._load_and_upload_map()
        self.action_client = ActionClient(self, NavigateToPose, 'navigate_to_pose')
        self.backup_client = ActionClient(self, BackUp, 'backup')
        self.initial_pose_publisher = self.create_publisher(
            PoseWithCovarianceStamped, '/initialpose', 10)
        self.lifecycle_client = self.create_client(
            ManageLifecycleNodes,
            '/lifecycle_manager_navigation/manage_nodes')
        self.create_subscription(
            DynamicJointState, '/dynamic_joint_states',
            self._status_callback, 10)
        self.docked = None
        self.pending_initial_pose = None
        self.initial_pose_remaining = 0
        self.lifecycle_future = None
        self.create_timer(1.0, self._complete_dock_pose)
        self.active_goal_handle = None
        self.active_command_id = None
        self.active_points = []
        self.active_point_index = 0
        self.active_is_patrol = False
        self.undocking = False
        self.undock_wait_timer = None
        self.busy = False
        self.create_timer(interval, self.poll_command)
        self.get_logger().info(f'Watching navigation command: {command_path}')

    def _connect_firestore(self):
        import firebase_admin
        from firebase_admin import credentials, firestore
        credential_path = Path(str(self.get_parameter('credential_path').value)).expanduser()
        if not credential_path.is_file():
            raise FileNotFoundError(f'Firebase credential not found: {credential_path}')
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(str(credential_path)))
        return firestore.client(), firestore

    def _load_and_upload_map(self) -> Dict[str, Any]:
        from carelink_patrol.fixed_map_upload import load_map, upload_verified
        payload, info = load_map(str(self.get_parameter('map_yaml_path').value))
        map_path = str(self.get_parameter('map_document_path').value).strip('/')
        upload_verified(self.db.document(map_path), payload,
                        self.firestore.SERVER_TIMESTAMP,
                        report=self.get_logger().warning)
        self.get_logger().info(
            f'Fixed map uploaded and verified: {map_path}, version={info["version"][:12]}')
        return info

    def _update(self, values: Dict[str, Any]) -> None:
        self.command_document.set(values, merge=True, timeout=5.0)

    def _claim_requested(self, command_id: str) -> bool:
        transaction = self.db.transaction()

        @self.firestore.transactional
        def claim(txn):
            snapshot = self.command_document.get(transaction=txn)
            current = snapshot.to_dict() or {}
            if (current.get('commandId') != command_id or
                    str(current.get('status', '')).upper() != 'REQUESTED'):
                return False
            txn.update(self.command_document, {
                'status': 'ACCEPTED', 'acceptedAt': self.firestore.SERVER_TIMESTAMP,
                'error': self.firestore.DELETE_FIELD,
            })
            return True
        return bool(claim(transaction))

    def poll_command(self) -> None:
        try:
            snapshot = self.command_document.get(timeout=5.0)
            if not snapshot.exists:
                return
            data = snapshot.to_dict() or {}
            if str(data.get('status', '')).upper() != 'REQUESTED':
                return
            command = str(data.get('command', '')).strip().upper()
            if command == 'CANCEL':
                self._handle_cancel(data)
            elif command == 'NAVIGATE':
                self._handle_navigate(data)
            elif command == 'PATROL':
                self._handle_patrol(data)
            elif command == 'SET_DOCK_POSE':
                self._handle_set_dock_pose(data)
            else:
                raise ValueError(
                    'command must be NAVIGATE, PATROL, SET_DOCK_POSE, '
                    'or CANCEL')
        except ValueError as error:
            self._fail(str(error))
        except Exception as error:
            self.get_logger().error(f'Firebase navigation poll failed: {error}')

    def _handle_navigate(self, data: Dict[str, Any]) -> None:
        command_id, x, y, app_yaw = parse_goal(data)
        yaw = app_yaw_to_map_yaw(app_yaw)
        map_version = data.get('mapVersion')
        if map_version != self.map_info['version']:
            raise ValueError('mapVersion does not match the robot fixed map')
        if self.busy:
            raise ValueError('another navigation goal is active')
        validate_goal_cell(x, y, self.map_info)
        timeout = float(self.get_parameter('action_server_timeout_sec').value)
        if not self.action_client.wait_for_server(timeout_sec=timeout):
            raise ValueError('Nav2 NavigateToPose action server is unavailable')
        if not self._claim_requested(command_id):
            return
        self.busy = True
        self.active_command_id = command_id
        self.active_points = [(x, y, yaw)]
        self.active_point_index = 0
        self.active_is_patrol = False
        self.undocking = False
        self._send_active_point()

    def _handle_patrol(self, data: Dict[str, Any]) -> None:
        command_id, points = parse_patrol(data)
        points = [
            (x, y, app_yaw_to_map_yaw(app_yaw))
            for x, y, app_yaw in points
        ]
        map_version = data.get('mapVersion')
        if map_version != self.map_info['version']:
            raise ValueError('mapVersion does not match the robot fixed map')
        if self.busy:
            raise ValueError('another navigation goal is active')
        for index, (x, y, _yaw) in enumerate(points, start=1):
            try:
                validate_goal_cell(x, y, self.map_info)
            except ValueError as error:
                raise ValueError(f'P{index}: {error}') from error
        timeout = float(self.get_parameter('action_server_timeout_sec').value)
        if not self.action_client.wait_for_server(timeout_sec=timeout):
            raise ValueError('Nav2 NavigateToPose action server is unavailable')
        if not self._claim_requested(command_id):
            return
        self.busy = True
        self.active_command_id = command_id
        self.active_points = build_round_trip(points)
        self.active_point_index = 0
        self.active_is_patrol = True
        if self.docked is True:
            if not self.backup_client.wait_for_server(timeout_sec=timeout):
                self._finish('FAILED', 'Nav2 BackUp action server is unavailable')
                return
            self._send_undock()
        else:
            self._send_active_point()

    def _status_callback(self, message: DynamicJointState) -> None:
        for index, joint_name in enumerate(message.joint_names):
            if (joint_name != 'carelink_status' or
                    index >= len(message.interface_values)):
                continue
            values = message.interface_values[index]
            for value_index, name in enumerate(values.interface_names):
                if name == 'dock_state' and value_index < len(values.values):
                    self.docked = values.values[value_index] >= 0.5
                    return

    def _handle_set_dock_pose(self, data: Dict[str, Any]) -> None:
        command_id, x, y, app_yaw = parse_goal(data)
        yaw = app_yaw_to_map_yaw(app_yaw)
        if data.get('mapVersion') != self.map_info['version']:
            raise ValueError('mapVersion does not match the robot fixed map')
        if self.docked is not True:
            raise ValueError(
                'robot must be physically connected to the charging dock')
        if self.busy or self.pending_initial_pose is not None:
            raise ValueError('another navigation command is active')
        validate_goal_cell(x, y, self.map_info)
        if not self._claim_requested(command_id):
            return
        pose_file = Path(
            str(self.get_parameter('dock_pose_file').value)).expanduser()
        try:
            save_pose_file(pose_file, x, y, yaw, self.map_info['version'])
        except OSError as error:
            self._fail(f'cannot save dock pose: {error}')
            return
        message = PoseWithCovarianceStamped()
        message.header.frame_id = 'map'
        message.pose.pose.position.x = x
        message.pose.pose.position.y = y
        message.pose.pose.orientation.z = math.sin(yaw / 2.0)
        message.pose.pose.orientation.w = math.cos(yaw / 2.0)
        message.pose.covariance[0] = message.pose.covariance[7] = 0.0025
        message.pose.covariance[35] = 0.01
        self.pending_initial_pose = message
        self.initial_pose_remaining = 3
        self.get_logger().info(
            f'Dock pose accepted: x={x:.3f}, y={y:.3f}, yaw={yaw:.3f}')

    def _complete_dock_pose(self) -> None:
        message = self.pending_initial_pose
        if message is None:
            return
        if self.initial_pose_remaining > 0:
            # A zero timestamp asks AMCL to use the latest available odom TF.
            # Using "now" here races the TF publisher and can reject the pose.
            self.initial_pose_publisher.publish(message)
            self.initial_pose_remaining -= 1
            return
        self._update({'status': 'SAVED',
                      'completedAt': self.firestore.SERVER_TIMESTAMP,
                      'error': self.firestore.DELETE_FIELD})
        self.get_logger().info(
            'Dock pose saved and applied; clean startup will activate Nav2')
        self.pending_initial_pose = None

    def _dock_pose_started(self, future) -> None:
        try:
            response = future.result()
            if not response.success:
                self._dock_pose_failed('Nav2 failed to activate; pose was saved')
                return
            self._update({'status': 'SAVED',
                          'completedAt': self.firestore.SERVER_TIMESTAMP,
                          'error': self.firestore.DELETE_FIELD})
            self.get_logger().info('Dock pose saved and Nav2 activated')
            self.pending_initial_pose = None
            self.lifecycle_future = None
        except Exception as error:
            self._dock_pose_failed(
                f'Nav2 activation failed: {error}; dock pose was saved')

    def _dock_pose_failed(self, message: str) -> None:
        self.pending_initial_pose = None
        self.lifecycle_future = None
        self._fail(message)

    def _send_active_point(self) -> None:
        x, y, yaw = self.active_points[self.active_point_index]
        pose = PoseStamped()
        pose.header.frame_id = 'map'
        # Use the latest available TF; a current timestamp can be ahead of
        # the odometry TF by a few milliseconds and cause extrapolation.
        pose.pose.position.x, pose.pose.position.y = x, y
        pose.pose.orientation.z = math.sin(yaw / 2.0)
        pose.pose.orientation.w = math.cos(yaw / 2.0)
        goal = NavigateToPose.Goal()
        goal.pose = pose
        if self.active_is_patrol:
            goal.behavior_tree = str(self.get_parameter(
                'patrol_behavior_tree').value)
        self.action_client.send_goal_async(goal).add_done_callback(self._goal_response)

    def _send_undock(self) -> None:
        goal = BackUp.Goal()
        goal.target.x = 0.30
        goal.target.y = 0.0
        goal.target.z = 0.0
        goal.speed = 0.05
        goal.time_allowance = Duration(sec=10)
        self.undocking = True
        self.get_logger().info('Undocking 0.30 m before patrol')
        self.backup_client.send_goal_async(goal).add_done_callback(self._undock_response)

    def _undock_response(self, future) -> None:
        try:
            handle = future.result()
            if not handle.accepted:
                self._finish('FAILED', 'Nav2 rejected the undock goal')
                return
            self.active_goal_handle = handle
            handle.get_result_async().add_done_callback(self._undock_result)
        except Exception as error:
            self._finish('FAILED', f'undock submission failed: {error}')

    def _undock_result(self, future) -> None:
        try:
            result = future.result().result
            if result.error_code != BackUp.Result.NONE:
                self._finish('FAILED', f'undock failed: {result.error_msg or result.error_code}')
                return
            self.undocking = False
            self.active_goal_handle = None
            self.get_logger().info('Undock complete; waiting for TF before P1')
            self.undock_wait_timer = self.create_timer(1.0, self._start_patrol_after_undock)
        except Exception as error:
            self._finish('FAILED', f'undock result failed: {error}')

    def _goal_response(self, future) -> None:
        try:
            handle = future.result()
            if not handle.accepted:
                self._finish('FAILED', 'Nav2 rejected the goal')
                return
            self.active_goal_handle = handle
            current_point = (
                [1, 2, 3, 2, 1][self.active_point_index]
                if self.active_is_patrol else 1)
            self._update({
                'status': 'MOVING', 'movingAt': self.firestore.SERVER_TIMESTAMP,
                'currentPoint': current_point,
                'totalPoints': 3 if self.active_is_patrol else 1,
                'currentLeg': self.active_point_index + 1,
                'totalLegs': len(self.active_points),
            })
            handle.get_result_async().add_done_callback(self._goal_result)
        except Exception as error:
            self._finish('FAILED', f'goal submission failed: {error}')

    def _goal_result(self, future) -> None:
        try:
            status = future.result().status
            if status == GoalStatus.STATUS_SUCCEEDED:
                if self.active_point_index + 1 < len(self.active_points):
                    self.active_point_index += 1
                    self.active_goal_handle = None
                    self._send_active_point()
                else:
                    self._finish('ARRIVED', None)
            elif status == GoalStatus.STATUS_CANCELED:
                self._finish('CANCELLED', None)
            else:
                self._finish('FAILED', f'Nav2 finished with status {status}')
        except Exception as error:
            self._finish('FAILED', f'Nav2 result failed: {error}')

    def _start_patrol_after_undock(self) -> None:
        if self.undock_wait_timer is not None:
            self.undock_wait_timer.cancel()
            self.undock_wait_timer = None
        if self.busy and self.active_is_patrol and self.active_points:
            self.get_logger().info('TF settle complete; starting patrol at P1')
            self._send_active_point()

    def _handle_cancel(self, data: Dict[str, Any]) -> None:
        cancel_id = data.get('commandId')
        target = data.get('targetCommandId')
        if not isinstance(cancel_id, str) or not cancel_id.strip():
            raise ValueError('cancel commandId must be a non-empty string')
        if not self.busy or self.active_goal_handle is None:
            raise ValueError('there is no active navigation goal')
        if target is not None and target != self.active_command_id:
            raise ValueError('targetCommandId does not match the active goal')
        if not self._claim_requested(cancel_id.strip()):
            return
        self._update({'status': 'CANCELLING'})
        self.active_goal_handle.cancel_goal_async().add_done_callback(
            lambda _future: self.get_logger().info('Nav2 cancel requested'))

    def _fail(self, message: str) -> None:
        self._update({'status': 'FAILED', 'error': message,
                      'completedAt': self.firestore.SERVER_TIMESTAMP})
        self.get_logger().error(message)

    def _finish(self, status: str, error: Any) -> None:
        values = {'status': status, 'completedAt': self.firestore.SERVER_TIMESTAMP}
        values['error'] = self.firestore.DELETE_FIELD if error is None else str(error)
        try:
            self._update(values)
        finally:
            self.busy = False
            self.active_goal_handle = None
            self.active_command_id = None
            self.active_points = []
            self.active_point_index = 0
            self.active_is_patrol = False
        self.undocking = False


def main(args=None) -> None:
    rclpy.init(args=args)
    node = None
    try:
        node = FirebaseNavBridge()
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
