#!/usr/bin/env python3
import unittest

from person_follow_control import FollowerConfig, compute_command, select_target


class PersonFollowControlTests(unittest.TestCase):
    def setUp(self):
        self.config = FollowerConfig()
        self.frame = (640, 480)

    def test_no_target_stops(self):
        command = compute_command(None, self.frame, self.config)
        self.assertEqual((command.linear, command.angular), (0.0, 0.0))

    def test_far_central_person_moves_forward(self):
        command = compute_command((270, 120, 100, 180), self.frame, self.config)
        self.assertGreater(command.linear, 0.0)
        self.assertAlmostEqual(command.angular, 0.0)

    def test_person_just_below_ninety_percent_moves_forward(self):
        command = compute_command((270, 25, 100, 431), self.frame, self.config)
        self.assertGreater(command.linear, 0.0)

    def test_person_at_ninety_percent_stops(self):
        command = compute_command((270, 24, 100, 432), self.frame, self.config)
        self.assertEqual(command.linear, 0.0)

    def test_left_person_turns_left(self):
        command = compute_command((20, 80, 100, 260), self.frame, self.config)
        self.assertGreater(command.angular, 0.0)

    def test_close_person_does_not_reverse_by_default(self):
        command = compute_command((180, 20, 280, 440), self.frame, self.config)
        self.assertEqual(command.linear, 0.0)

    def test_lying_person_stops(self):
        command = compute_command((100, 250, 300, 120), self.frame, self.config)
        self.assertEqual((command.linear, command.angular), (0.0, 0.0))

    def test_tracker_keeps_near_previous_person(self):
        previous = (100, 90, 130, 280)
        people = [((105, 92, 130, 280), 0.80), ((390, 80, 160, 320), 0.95)]
        selected = select_target(people, previous, self.frame)
        self.assertEqual(selected[0], people[0][0])


if __name__ == "__main__":
    unittest.main()
