#!/usr/bin/env python3
"""Share one camera and YOLO inference between fall alerts and following."""
import sys
import time
from pathlib import Path

CAMERA_STACK = Path('/home/carelink/camera_stack')
sys.path.append(str(CAMERA_STACK))

import rclpy
from rclpy.executors import ExternalShutdownException
from firebase_detector_runner import firebase_detector
from firebase_follow_control import FirebaseFollowControl
from person_follower import PersonFollowerNode, parse_args
from shared_person_detector import SharedPersonDetector
from yolo_fall_detector import Camera


def main():
    args = parse_args()
    camera = detector = control = follower = None
    rclpy.init()
    try:
        camera = Camera()
        detector = firebase_detector(camera, args.confidence)
        detector.start()
        credential = Path(args.firebase_credential)
        if not credential.is_absolute():
            credential = Path(__file__).resolve().parent / credential
        control = FirebaseFollowControl(credential, args.firebase_document, args.firebase_poll)
        control.start()
        shared = SharedPersonDetector(detector)
        follower = PersonFollowerNode(shared, control, args)
        started = last_log = time.monotonic()
        while rclpy.ok():
            rclpy.spin_once(follower, timeout_sec=0.02)
            if not detector.is_alive():
                raise RuntimeError('Shared YOLO detector stopped')
            now = time.monotonic()
            if now - last_log >= 5:
                result = shared.snapshot()
                follower.get_logger().info(
                    f'Follow status: {follower.last_command.reason}; '
                    f'people={len(result["people"])}; '
                    f'YOLO={result["inference_ms"]:.0f}ms; '
                    f'front={follower.front_obstacle}; '
                    f'v={follower.last_command.linear:.3f}; '
                    f'w={follower.last_command.angular:.3f}')
                last_log = now
            if args.seconds and now - started >= args.seconds:
                break
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        if follower is not None and rclpy.ok():
            follower.stop()
        if control is not None:
            control.close()
            control.join(timeout=2)
        if detector is not None:
            detector.running = False
            detector.join(timeout=2)
        if camera is not None:
            camera.close()
        if follower is not None:
            follower.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
