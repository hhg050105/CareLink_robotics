#!/usr/bin/env python3
"""Follow one detected person and publish conservative ROS 2 velocity commands."""

import argparse
import threading
import time
from dataclasses import replace
from pathlib import Path
from typing import Optional

import cv2
import onnxruntime as ort
import rclpy
from geometry_msgs.msg import Twist, TwistStamped
from std_msgs.msg import Bool
from rclpy.node import Node
from sensor_msgs.msg import LaserScan

from firebase_follow_control import FirebaseFollowControl
from person_follow_control import Command, FollowerConfig, compute_command, select_target
from yolo_fall_detector import Camera, detect


class PersonDetector(threading.Thread):
    def __init__(self, camera: Camera, model_path: Path, confidence: float):
        super().__init__(daemon=True)
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(
            str(model_path), sess_options=options, providers=["CPUExecutionProvider"]
        )
        self.camera = camera
        self.confidence = confidence
        self.lock = threading.Lock()
        self.running = True
        self.enabled = threading.Event()
        self.last_sequence = -1
        self.previous_box = None
        self.misses = 0
        self.result = {
            "people": [], "target": None, "updated_at": 0.0,
            "inference_ms": 0.0, "frame_size": (640, 480),
        }

    def snapshot(self):
        with self.lock:
            copied = dict(self.result)
            copied["people"] = list(self.result["people"])
            return copied

    def set_enabled(self, enabled: bool):
        """Run inference only while person-follow mode is active."""
        if enabled:
            self.enabled.set()
            return
        if self.enabled.is_set():
            self.enabled.clear()
            self.previous_box = None
            self.misses = 0
            with self.lock:
                self.result = {
                    "people": [], "target": None, "updated_at": 0.0,
                    "inference_ms": 0.0, "frame_size": self.result["frame_size"],
                }

    def run(self):
        while self.running:
            if not self.enabled.wait(timeout=0.1):
                continue
            sequence, frame = self.camera.latest()
            if frame is None or sequence == self.last_sequence:
                time.sleep(0.005)
                continue
            self.last_sequence = sequence
            started = time.monotonic()
            people = detect(self.session, frame, self.confidence)
            frame_size = (frame.shape[1], frame.shape[0])
            target = select_target(people, self.previous_box, frame_size)

            if target is None:
                self.misses += 1
                # Do not jump to a different person on the first two mismatches.
                if people and self.previous_box is not None and self.misses >= 3:
                    target = select_target(people, None, frame_size)
            if target is not None:
                self.previous_box = target[0]
                self.misses = 0
            elif self.misses >= 3:
                self.previous_box = None

            now = time.monotonic()
            with self.lock:
                self.result = {
                    "people": people,
                    "target": target,
                    "updated_at": now,
                    "inference_ms": (now - started) * 1000.0,
                    "frame_size": frame_size,
                }


class PersonFollowerNode(Node):
    def __init__(self, detector: PersonDetector, firebase_control, args):
        super().__init__("carelink_person_follower")
        self.detector = detector
        self.firebase_control = firebase_control
        self.args = args
        self.config = FollowerConfig(
            target_height_ratio=args.target_height_ratio,
            height_deadband=args.height_deadband,
            center_deadband=args.center_deadband,
            linear_kp=args.linear_kp,
            angular_kp=args.angular_kp,
            max_linear=args.max_linear,
            max_reverse=args.max_reverse,
            max_angular=args.max_angular,
            turn_in_place_error=args.turn_in_place_error,
            lying_ratio=args.lying_ratio,
            allow_reverse=args.allow_reverse,
            stop_on_lying=not args.ignore_lying,
        )
        message_type = Twist if args.unstamped else TwistStamped
        self.publisher = self.create_publisher(message_type, args.cmd_topic, 10)
        self.mode_publisher = self.create_publisher(
            Bool, '/carelink/person_follow_active', 10)
        self.scan_subscription = self.create_subscription(
            LaserScan, args.scan_topic, self._scan_callback, 10
        )
        self.latest_scan_at = 0.0
        self.front_obstacle: Optional[float] = None
        self.last_linear = 0.0
        self.last_angular = 0.0
        self.last_tick = time.monotonic()
        self.last_command = Command(0.0, 0.0, 0.0, 0.0, "STARTING")
        self.last_firebase_state = None
        self.timer = self.create_timer(1.0 / args.control_rate, self._control_tick)
        mode = "ENABLED" if args.enable_motion else "DRY RUN"
        self.get_logger().info(
            f"Person follower {mode}; publishing to {args.cmd_topic}; "
            f"LiDAR safety {'disabled' if args.no_lidar else 'required'}"
        )

    def _scan_callback(self, scan: LaserScan):
        half_sector = self.args.scan_sector_degrees * 3.141592653589793 / 360.0
        valid = []
        for index, distance in enumerate(scan.ranges):
            angle = scan.angle_min + index * scan.angle_increment
            if abs(angle) <= half_sector and scan.range_min <= distance <= scan.range_max:
                valid.append(distance)
        self.front_obstacle = min(valid) if valid else None
        self.latest_scan_at = time.monotonic()

    @staticmethod
    def _slew(current: float, target: float, limit_per_second: float, dt: float) -> float:
        maximum_change = limit_per_second * max(dt, 0.0)
        return current + max(-maximum_change, min(maximum_change, target - current))

    def _publish(self, linear: float, angular: float):
        if self.args.unstamped:
            message = Twist()
            message.linear.x = linear
            message.angular.z = angular
        else:
            message = TwistStamped()
            message.header.stamp = self.get_clock().now().to_msg()
            message.header.frame_id = "base_link"
            message.twist.linear.x = linear
            message.twist.angular.z = angular
        self.publisher.publish(message)

    def _control_tick(self):
        now = time.monotonic()
        mode, connected = "STOP", False
        if self.firebase_control is not None:
            mode, connected, error, _updated_at = self.firebase_control.snapshot()
            firebase_state = (mode, connected, error)
            if firebase_state != self.last_firebase_state:
                if connected:
                    self.get_logger().info(f"Firebase person-follow mode: {mode}")
                else:
                    self.get_logger().error(
                        f"Firebase control unavailable; forcing STOP: {error}"
                    )
                self.last_firebase_state = firebase_state

        follow_requested = bool(
            self.firebase_control is None or (connected and mode == "FOLLOW"))
        self.detector.set_enabled(follow_requested)
        snapshot = self.detector.snapshot()
        target_detection = snapshot["target"]
        target_box = target_detection[0] if target_detection is not None else None
        command = compute_command(target_box, snapshot["frame_size"], self.config)
        if self.firebase_control is not None and not connected:
            command = replace(
                command, linear=0.0, angular=0.0,
                reason="FIREBASE OFFLINE - STOP")
        elif self.firebase_control is not None and mode != "FOLLOW":
            command = replace(
                command, linear=0.0, angular=0.0, reason="APP STOP")

        follow_active = Bool()
        follow_active.data = bool(
            self.args.enable_motion and self.firebase_control is not None and
            follow_requested)
        self.mode_publisher.publish(follow_active)

        if now - snapshot["updated_at"] > self.args.watchdog:
            command = replace(command, linear=0.0, angular=0.0, reason="CAMERA WATCHDOG - STOP")
        elif not self.args.no_lidar:
            if now - self.latest_scan_at > self.args.scan_watchdog:
                command = replace(command, linear=0.0, angular=0.0, reason="LIDAR WATCHDOG - STOP")
            elif self.front_obstacle is None:
                command = replace(command, linear=0.0, angular=0.0, reason="NO VALID LIDAR RANGE - STOP")
            elif self.front_obstacle < self.args.obstacle_stop_distance:
                command = replace(command, linear=0.0, angular=0.0, reason="OBSTACLE - STOP")

        if not self.args.enable_motion:
            command = replace(command, linear=0.0, angular=0.0, reason=f"DRY RUN | {command.reason}")

        safety_stop = command.linear == 0.0 and command.angular == 0.0 and (
            "STOP" in command.reason or "NO TARGET" in command.reason or "DRY RUN" in command.reason
        )
        dt = now - self.last_tick
        self.last_tick = now
        if safety_stop:
            self.last_linear = 0.0
            self.last_angular = 0.0
        else:
            self.last_linear = self._slew(
                self.last_linear, command.linear, self.args.linear_accel, dt
            )
            self.last_angular = self._slew(
                self.last_angular, command.angular, self.args.angular_accel, dt
            )
        self.last_command = replace(
            command, linear=self.last_linear, angular=self.last_angular
        )
        self._publish(self.last_linear, self.last_angular)

    def stop(self):
        self.last_linear = 0.0
        self.last_angular = 0.0
        for _ in range(5):
            self._publish(0.0, 0.0)
            time.sleep(0.03)


def parse_args():
    parser = argparse.ArgumentParser(
        description="OV5647 + ONNX Runtime person follower for ROS 2 Jazzy"
    )
    parser.add_argument("--model", default="models/yolo11n.onnx")
    parser.add_argument("--confidence", type=float, default=0.35)
    parser.add_argument("--cmd-topic", default="/diff_cont/cmd_vel")
    parser.add_argument("--unstamped", action="store_true", help="Publish Twist instead of TwistStamped")
    parser.add_argument("--scan-topic", default="/scan")
    parser.add_argument("--no-lidar", action="store_true", help="Disable LiDAR interlock (clear test area only)")
    parser.add_argument("--scan-sector-degrees", type=float, default=50.0)
    parser.add_argument("--obstacle-stop-distance", type=float, default=0.45)
    parser.add_argument("--scan-watchdog", type=float, default=0.80)
    parser.add_argument("--watchdog", type=float, default=0.75)
    parser.add_argument("--control-rate", type=float, default=10.0)
    parser.add_argument("--target-height-ratio", type=float, default=0.90)
    parser.add_argument("--height-deadband", type=float, default=0.0)
    parser.add_argument("--center-deadband", type=float, default=0.08)
    parser.add_argument("--turn-in-place-error", type=float, default=0.45)
    parser.add_argument("--linear-kp", type=float, default=0.80)
    parser.add_argument("--angular-kp", type=float, default=1.20)
    parser.add_argument("--max-linear", type=float, default=0.30)
    parser.add_argument("--max-reverse", type=float, default=0.10)
    parser.add_argument("--max-angular", type=float, default=0.65)
    parser.add_argument("--linear-accel", type=float, default=0.60)
    parser.add_argument("--angular-accel", type=float, default=1.50)
    parser.add_argument("--lying-ratio", type=float, default=1.10)
    parser.add_argument("--allow-reverse", action="store_true")
    parser.add_argument("--ignore-lying", action="store_true")
    parser.add_argument("--enable-motion", action="store_true", help="Actually move the robot")
    parser.add_argument(
        "--no-firebase-control",
        action="store_true",
        help="Ignore Firestore mode (local testing only)",
    )
    parser.add_argument(
        "--firebase-document",
        default="robots/carelink-01/control/personFollower",
    )
    parser.add_argument(
        "--firebase-credential",
        default="secrets/firebase-service-account.json",
    )
    parser.add_argument("--firebase-poll", type=float, default=1.0)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--display-scale", type=float, default=0.75)
    parser.add_argument("--seconds", type=float, default=0.0)
    return parser.parse_args()


def draw_preview(frame, snapshot, command, front_obstacle):
    for (x, y, width, height), confidence in snapshot["people"]:
        colour = (80, 180, 80)
        cv2.rectangle(frame, (x, y), (x + width, y + height), colour, 1)
        cv2.putText(frame, f"person {confidence:.2f}", (x, max(20, y - 5)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, colour, 1)
    if snapshot["target"] is not None:
        (x, y, width, height), _confidence = snapshot["target"]
        cv2.rectangle(frame, (x, y), (x + width, y + height), (0, 255, 255), 3)
        cv2.circle(frame, (x + width // 2, y + height // 2), 5, (0, 255, 255), -1)
    centre = frame.shape[1] // 2
    cv2.line(frame, (centre, 0), (centre, frame.shape[0]), (255, 120, 0), 1)
    lidar_text = "n/a" if front_obstacle is None else f"{front_obstacle:.2f}m"
    cv2.putText(frame, command.reason, (12, 28), cv2.FONT_HERSHEY_SIMPLEX,
                0.62, (0, 255, 255), 2)
    cv2.putText(
        frame,
        f"v={command.linear:+.2f} m/s  w={command.angular:+.2f} rad/s  "
        f"YOLO={snapshot['inference_ms']:.0f} ms  front={lidar_text}",
        (12, 55), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (255, 255, 255), 1,
    )


def main():
    args = parse_args()
    if args.display_scale <= 0:
        raise ValueError("--display-scale must be greater than 0")
    if args.firebase_poll <= 0:
        raise ValueError("--firebase-poll must be greater than 0")
    project_dir = Path(__file__).resolve().parent
    model_path = Path(args.model)
    if not model_path.is_absolute():
        model_path = project_dir / model_path
    if not model_path.is_file():
        raise FileNotFoundError(f"YOLO model not found: {model_path}")

    rclpy.init()
    camera = Camera()
    detector = PersonDetector(camera, model_path, args.confidence)
    detector.start()
    firebase_control = None
    if not args.no_firebase_control:
        credential_path = Path(args.firebase_credential)
        if not credential_path.is_absolute():
            credential_path = project_dir / credential_path
        firebase_control = FirebaseFollowControl(
            credential_path,
            args.firebase_document,
            args.firebase_poll,
        )
        firebase_control.start()
    follower = PersonFollowerNode(detector, firebase_control, args)
    started = time.monotonic()

    try:
        while rclpy.ok():
            rclpy.spin_once(follower, timeout_sec=0.02)
            if not args.headless:
                _sequence, frame = camera.latest()
                if frame is not None:
                    snapshot = detector.snapshot()
                    draw_preview(frame, snapshot, follower.last_command, follower.front_obstacle)
                    if args.display_scale != 1.0:
                        frame = cv2.resize(
                            frame, None, fx=args.display_scale, fy=args.display_scale
                        )
                    cv2.imshow("CareLink person follower", frame)
                    if cv2.waitKey(1) & 255 in (27, ord("q")):
                        break
            if args.seconds and time.monotonic() - started >= args.seconds:
                break
    except KeyboardInterrupt:
        pass
    finally:
        follower.stop()
        if firebase_control is not None:
            firebase_control.close()
            firebase_control.join(timeout=2.0)
        detector.running = False
        detector.join(timeout=2.0)
        camera.close()
        follower.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
