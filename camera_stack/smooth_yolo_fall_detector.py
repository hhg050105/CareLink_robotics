#!/usr/bin/env python3
"""Smooth preview with asynchronous YOLO inference on the latest frame."""

import argparse
import threading
import time
from collections import deque
from pathlib import Path

import cv2
import onnxruntime as ort

from yolo_fall_detector import Camera, detect


class Detector(threading.Thread):
    def __init__(self, camera, confidence):
        super().__init__(daemon=True)
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(
            "models/yolo11n.onnx", sess_options=options,
            providers=["CPUExecutionProvider"]
        )
        self.camera = camera
        self.confidence = confidence
        self.lock = threading.Lock()
        self.result = {"people": [], "state": "STARTING", "ms": 0, "alarm": False}
        self.running = True
        self.last_sequence = -1
        self.history = deque(maxlen=12)
        self.lying_since = None
        self.candidate_until = 0.0
        self.alarm_until = 0.0
        self.output = Path("artifacts/falls")
        self.output.mkdir(parents=True, exist_ok=True)

    def snapshot(self):
        with self.lock:
            return dict(self.result)

    def run(self):
        while self.running:
            sequence, frame = self.camera.latest()
            if frame is None or sequence == self.last_sequence:
                time.sleep(0.005)
                continue
            self.last_sequence = sequence
            started = time.monotonic()
            people = detect(self.session, frame, self.confidence)
            now = time.monotonic()
            state = "NO PERSON"

            if people:
                (x, y, width, height), confidence = max(
                    people, key=lambda item: item[0][2] * item[0][3]
                )
                centre_y = y + height / 2
                self.history.append((now, centre_y))
                recent = [cy for timestamp, cy in self.history if timestamp > now - 1.5]
                drop = centre_y - min(recent, default=centre_y)
                ratio = width / max(height, 1)
                if drop > frame.shape[0] * 0.12:
                    self.candidate_until = now + 3.0
                if ratio > 1.1:
                    self.lying_since = self.lying_since or now
                    state = "LYING"
                    if now - self.lying_since > 1.2 and now < self.candidate_until:
                        state = "FALL DETECTED"
                        if now >= self.alarm_until:
                            self.alarm_until = now + 10.0
                            path = self.output / f"fall-{time.strftime('%Y%m%d-%H%M%S')}.jpg"
                            cv2.imwrite(str(path), frame)
                            print(f"FALL_DETECTED {path}", flush=True)
                else:
                    self.lying_since = None
                    state = "PERSON"

            with self.lock:
                self.result = {
                    "people": people, "state": state,
                    "ms": (now - started) * 1000,
                    "alarm": now < self.alarm_until,
                }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--confidence", type=float, default=0.35)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--seconds", type=float, default=0)
    parser.add_argument("--display-scale", type=float, default=0.75)
    args = parser.parse_args()

    camera = Camera()
    detector = Detector(camera, args.confidence)
    detector.start()
    started = time.monotonic()
    frames = 0
    fps_started = started
    preview_fps = 0.0

    try:
        while True:
            _, frame = camera.latest()
            if frame is None:
                time.sleep(0.005)
                continue
            result = detector.snapshot()
            colour = (0, 0, 255) if result["alarm"] else (0, 255, 0)
            for (x, y, width, height), confidence in result["people"]:
                cv2.rectangle(frame, (x, y), (x + width, y + height), colour, 2)
                cv2.putText(frame, f"person {confidence:.2f}", (x, max(20, y - 6)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.52, colour, 2)
            frames += 1
            now = time.monotonic()
            if now - fps_started >= 1.0:
                preview_fps = frames / (now - fps_started)
                frames, fps_started = 0, now
            cv2.putText(frame, f"{result['state']} | view {preview_fps:.0f} FPS | YOLO {result['ms']:.0f} ms",
                        (12, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (0, 255, 255), 2)
            if not args.headless:
                if args.display_scale != 1.0:
                    frame = cv2.resize(frame, None, fx=args.display_scale, fy=args.display_scale)
                cv2.imshow("Smooth YOLO fall detector", frame)
                if cv2.waitKey(1) & 255 in (27, ord("q")):
                    break
            else:
                time.sleep(1 / 30)
            if args.seconds and now - started >= args.seconds:
                break
    finally:
        detector.running = False
        detector.join(timeout=2)
        camera.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
