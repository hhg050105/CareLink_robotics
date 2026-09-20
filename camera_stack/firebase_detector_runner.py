#!/usr/bin/env python3
"""Run the smooth detector with Firebase fall reporting."""

from firebase_alert import FirebaseAlert
from smooth_yolo_fall_detector import Detector, main


def firebase_detector(camera, confidence):
    alert = FirebaseAlert()
    return Detector(camera, confidence, on_fall=alert.send_fall)


if __name__ == "__main__":
    main(detector_factory=firebase_detector)
