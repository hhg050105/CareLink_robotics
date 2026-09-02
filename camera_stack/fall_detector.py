#!/usr/bin/env python3
"""Camera-connected fall detection baseline for controlled testing.

This is a motion/shape baseline, not a safety-certified detector. It detects a
large foreground object moving downward and then remaining in a wide posture.
"""

import argparse
import time
from collections import deque
from pathlib import Path

import cv2


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--seconds", type=float, default=0, help="Stop after N seconds; 0 runs forever")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--output", type=Path, default=Path("artifacts/falls"))
    parser.add_argument("--min-area", type=float, default=0.035, help="Minimum foreground fraction")
    parser.add_argument("--lying-ratio", type=float, default=1.25, help="Width/height threshold")
    parser.add_argument("--hold-seconds", type=float, default=1.5)
    return parser.parse_args()


def main():
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(args.camera, cv2.CAP_V4L2)
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    if not capture.isOpened():
        raise SystemExit("Unable to open camera")

    subtractor = cv2.createBackgroundSubtractorMOG2(history=300, varThreshold=32, detectShadows=True)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    centres = deque(maxlen=20)
    started = time.monotonic()
    lying_since = None
    alarm_latched = False
    warmup_seconds = 3.0

    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                print("Camera frame read failed", flush=True)
                break

            now = time.monotonic()
            mask = subtractor.apply(frame)
            mask[mask < 250] = 0
            mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
            mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)

            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            minimum_area = frame.shape[0] * frame.shape[1] * args.min_area
            contour = max(contours, key=cv2.contourArea, default=None)
            state = "CALIBRATING" if now - started < warmup_seconds else "NO PERSON"

            if contour is not None and cv2.contourArea(contour) >= minimum_area:
                x, y, width, height = cv2.boundingRect(contour)
                centre_y = y + height / 2
                centres.append((now, centre_y))
                ratio = width / max(height, 1)

                cutoff = now - 1.2
                recent = [(t, cy) for t, cy in centres if t >= cutoff]
                downward_motion = 0.0
                if len(recent) >= 2:
                    downward_motion = recent[-1][1] - min(cy for _, cy in recent)

                is_lying = ratio >= args.lying_ratio
                fell_quickly = downward_motion >= frame.shape[0] * 0.12

                if now - started < warmup_seconds:
                    state = "CALIBRATING"
                elif is_lying:
                    lying_since = lying_since or now
                    state = "POSSIBLE FALL" if fell_quickly else "LYING"
                    if now - lying_since >= args.hold_seconds and (fell_quickly or alarm_latched):
                        state = "FALL DETECTED"
                        if not alarm_latched:
                            alarm_latched = True
                            stamp = time.strftime("%Y%m%d-%H%M%S")
                            path = args.output / f"fall-{stamp}.jpg"
                            cv2.imwrite(str(path), frame)
                            print(f"FALL_DETECTED snapshot={path}", flush=True)
                else:
                    lying_since = None
                    state = "UPRIGHT/MOVING"

                colour = (0, 0, 255) if alarm_latched else (0, 255, 255)
                cv2.rectangle(frame, (x, y), (x + width, y + height), colour, 2)
                cv2.putText(frame, f"ratio={ratio:.2f} drop={downward_motion:.0f}px", (x, max(20, y - 8)),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.5, colour, 1, cv2.LINE_AA)

            text_colour = (0, 0, 255) if alarm_latched else (0, 255, 0)
            cv2.putText(frame, state, (15, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.9, text_colour, 2, cv2.LINE_AA)

            if not args.headless:
                cv2.imshow("Fall detection baseline", frame)
                key = cv2.waitKey(1) & 0xFF
                if key in (27, ord("q")):
                    break

            if args.seconds and now - started >= args.seconds:
                break
    finally:
        capture.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
