#!/usr/bin/env python3
"""Run the smooth detector with Firebase reporting injected safely."""

from pathlib import Path

source_path = Path(__file__).with_name("smooth_yolo_fall_detector.py")
source = source_path.read_text()
source = source.replace(
    "from yolo_fall_detector import Camera, detect",
    "from yolo_fall_detector import Camera, detect\nfrom firebase_alert import FirebaseAlert",
)
source = source.replace(
    'self.output.mkdir(parents=True, exist_ok=True)',
    'self.output.mkdir(parents=True, exist_ok=True)\n        self.firebase = FirebaseAlert()',
)
source = source.replace(
    'print(f"FALL_DETECTED {path}", flush=True)',
    'print(f"FALL_DETECTED {path}", flush=True)\n                            self.firebase.send_fall(confidence, ratio, drop, path)',
)
namespace = {"__name__": "__main__", "__file__": str(source_path)}
exec(compile(source, str(source_path), "exec"), namespace)
