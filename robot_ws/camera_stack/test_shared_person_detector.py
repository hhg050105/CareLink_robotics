import unittest
from shared_person_detector import SharedPersonDetector


class FakeDetector:
    def __init__(self):
        self.result = dict(people=[((200, 100, 100, 200), .9)], ms=80,
                           updated_at=10., frame_size=(640, 480))

    def snapshot(self):
        return dict(self.result)


class SharedDetectorTests(unittest.TestCase):
    def setUp(self):
        self.source = FakeDetector()
        self.shared = SharedPersonDetector(self.source)
        self.shared.set_enabled(True)

    def test_stalled_inference_keeps_original_timestamp(self):
        self.assertEqual(self.shared.snapshot()['updated_at'], 10.)
        self.assertEqual(self.shared.snapshot()['updated_at'], 10.)

    def test_stop_clears_target_without_stopping_fall_detection(self):
        self.assertIsNotNone(self.shared.snapshot()['target'])
        self.shared.set_enabled(False)
        self.assertIsNone(self.shared.snapshot()['target'])
        self.assertEqual(self.shared.snapshot()['people'], [])
        self.assertEqual(len(self.source.result['people']), 1)

    def test_target_disappears_on_next_empty_frame(self):
        self.assertIsNotNone(self.shared.snapshot()['target'])
        self.source.result.update(people=[], updated_at=11.)
        self.assertIsNone(self.shared.snapshot()['target'])


if __name__ == '__main__':
    unittest.main()
