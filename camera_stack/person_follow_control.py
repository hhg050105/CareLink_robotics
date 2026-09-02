#!/usr/bin/env python3
"""Pure person-following control logic, independent of ROS and the camera."""

from dataclasses import dataclass
from math import hypot
from typing import Optional, Sequence, Tuple


BBox = Tuple[int, int, int, int]
Detection = Tuple[BBox, float]


@dataclass(frozen=True)
class FollowerConfig:
    target_height_ratio: float = 0.90
    height_deadband: float = 0.0
    center_deadband: float = 0.08
    linear_kp: float = 0.80
    angular_kp: float = 1.20
    max_linear: float = 0.30
    max_reverse: float = 0.10
    max_angular: float = 0.65
    turn_in_place_error: float = 0.45
    lying_ratio: float = 1.10
    allow_reverse: bool = False
    stop_on_lying: bool = True


@dataclass(frozen=True)
class Command:
    linear: float
    angular: float
    center_error: float
    height_ratio: float
    reason: str


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def bbox_iou(first: BBox, second: BBox) -> float:
    ax, ay, aw, ah = first
    bx, by, bw, bh = second
    left = max(ax, bx)
    top = max(ay, by)
    right = min(ax + aw, bx + bw)
    bottom = min(ay + ah, by + bh)
    intersection = max(0, right - left) * max(0, bottom - top)
    union = aw * ah + bw * bh - intersection
    return intersection / union if union > 0 else 0.0


def _normalized_center_distance(first: BBox, second: BBox, frame_size: Tuple[int, int]) -> float:
    frame_width, frame_height = frame_size
    ax, ay, aw, ah = first
    bx, by, bw, bh = second
    distance = hypot((ax + aw / 2) - (bx + bw / 2), (ay + ah / 2) - (by + bh / 2))
    diagonal = max(hypot(frame_width, frame_height), 1.0)
    return distance / diagonal


def select_target(
    people: Sequence[Detection],
    previous: Optional[BBox],
    frame_size: Tuple[int, int],
) -> Optional[Detection]:
    """Keep the current person when possible; otherwise acquire a large central person."""
    if not people:
        return None

    frame_width, frame_height = frame_size
    if previous is not None:
        ranked = []
        for detection in people:
            box, confidence = detection
            overlap = bbox_iou(previous, box)
            distance = _normalized_center_distance(previous, box, frame_size)
            if overlap >= 0.05 or distance <= 0.22:
                ranked.append((2.0 * overlap - distance + 0.1 * confidence, detection))
        if ranked:
            return max(ranked, key=lambda item: item[0])[1]

    def acquisition_score(detection: Detection) -> float:
        (x, y, width, height), confidence = detection
        area_ratio = (width * height) / max(frame_width * frame_height, 1)
        center_offset = abs((x + width / 2) - frame_width / 2) / max(frame_width / 2, 1)
        return area_ratio * 4.0 + confidence * 0.2 - center_offset * 0.15

    return max(people, key=acquisition_score)


def compute_command(
    target: Optional[BBox],
    frame_size: Tuple[int, int],
    config: FollowerConfig,
) -> Command:
    """Convert a tracked person's image position and size into a base velocity."""
    if target is None:
        return Command(0.0, 0.0, 0.0, 0.0, "NO TARGET")

    frame_width, frame_height = frame_size
    x, _y, width, height = target
    if frame_width <= 0 or frame_height <= 0 or width <= 0 or height <= 0:
        return Command(0.0, 0.0, 0.0, 0.0, "INVALID TARGET")

    center_error = ((x + width / 2) - frame_width / 2) / (frame_width / 2)
    height_ratio = height / frame_height
    if config.stop_on_lying and width / height >= config.lying_ratio:
        return Command(0.0, 0.0, center_error, height_ratio, "LYING - STOP")

    angular_error = center_error if abs(center_error) > config.center_deadband else 0.0
    # Positive ROS angular.z turns left. A target on the image's left has a negative error.
    angular = clamp(-config.angular_kp * angular_error, -config.max_angular, config.max_angular)

    distance_error = config.target_height_ratio - height_ratio
    if abs(distance_error) <= config.height_deadband:
        linear = 0.0
        reason = "HOLD DISTANCE"
    elif distance_error > 0:
        linear = clamp(config.linear_kp * distance_error, 0.0, config.max_linear)
        reason = "FOLLOW"
    elif config.allow_reverse:
        linear = clamp(config.linear_kp * distance_error, -config.max_reverse, 0.0)
        reason = "TOO CLOSE - REVERSE"
    else:
        linear = 0.0
        reason = "TOO CLOSE - STOP"

    if abs(center_error) >= config.turn_in_place_error:
        linear = 0.0
        reason = "TURN IN PLACE"
    elif linear > 0:
        linear *= max(0.20, 1.0 - abs(center_error) / config.turn_in_place_error)

    return Command(linear, angular, center_error, height_ratio, reason)
