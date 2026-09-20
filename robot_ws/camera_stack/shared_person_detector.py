"""Adapt one fall detector's results for the person-follow controller."""
from person_follow_control import select_target


class SharedPersonDetector:
    def __init__(self, detector):
        self.detector = detector
        self.enabled = False
        self.previous_box = None
        self.last_update = None
        self.target = None

    def set_enabled(self, enabled):
        if not enabled:
            self.previous_box = None
            self.target = None
            self.last_update = None
        self.enabled = enabled

    def snapshot(self):
        result = self.detector.snapshot()
        updated_at = result.get('updated_at', 0.0)
        frame_size = result.get('frame_size', (640, 480))
        people = result['people'] if self.enabled else []
        if self.enabled and updated_at != self.last_update:
            self.target = select_target(people, self.previous_box, frame_size)
            self.previous_box = self.target[0] if self.target is not None else None
            self.last_update = updated_at
        return dict(people=people, target=self.target, updated_at=updated_at,
                    frame_size=frame_size, inference_ms=result['ms'])
