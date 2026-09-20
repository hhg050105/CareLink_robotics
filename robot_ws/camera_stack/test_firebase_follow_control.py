#!/usr/bin/env python3
import unittest

from firebase_follow_control import FirebaseFollowControl


class FirebaseFollowControlTests(unittest.TestCase):
    def test_mode_field_accepts_follow_case_insensitively(self):
        self.assertEqual(FirebaseFollowControl.mode_from_data({"mode": "follow"}), "FOLLOW")

    def test_mode_field_accepts_stop(self):
        self.assertEqual(FirebaseFollowControl.mode_from_data({"mode": "STOP"}), "STOP")

    def test_boolean_compatibility(self):
        self.assertEqual(FirebaseFollowControl.mode_from_data({"enabled": True}), "FOLLOW")
        self.assertEqual(FirebaseFollowControl.mode_from_data({"enabled": False}), "STOP")

    def test_unknown_or_missing_value_fails_safe(self):
        self.assertEqual(FirebaseFollowControl.mode_from_data({"mode": "PATROL"}), "STOP")
        self.assertEqual(FirebaseFollowControl.mode_from_data({}), "STOP")


if __name__ == "__main__":
    unittest.main()
