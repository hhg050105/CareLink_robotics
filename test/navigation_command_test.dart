import 'dart:math' as math;

import 'package:carelink/models/navigation_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigationYaw', () {
    test('screen right maps to ROS yaw 0', () {
      expect(NavigationYaw.fromScreenVector(1, 0), closeTo(0, 1e-12));
    });

    test('screen up maps to ROS yaw +pi/2', () {
      expect(
        NavigationYaw.fromScreenVector(0, -1),
        closeTo(math.pi / 2, 1e-12),
      );
    });

    test('screen down maps to ROS yaw -pi/2', () {
      expect(
        NavigationYaw.fromScreenVector(0, 1),
        closeTo(-math.pi / 2, 1e-12),
      );
    });

    test('screen left maps to the normalized ROS yaw -pi', () {
      expect(NavigationYaw.fromScreenVector(-1, 0), closeTo(-math.pi, 1e-12));
    });

    test('clockwise screen angle is negated and normalized', () {
      expect(
        NavigationYaw.fromScreenClockwiseAngle(math.pi / 2),
        closeTo(-math.pi / 2, 1e-12),
      );
    });

    test('dock position to P1 is approximately -1.506 rad', () {
      final yaw = NavigationYaw.betweenWorldPoints(
        fromX: -0.0810507663,
        fromY: 0.4611513410,
        toX: -0.03,
        toY: -0.32,
      );
      expect(yaw, closeTo(-1.50554, 0.00001));
    });

    test('angles beyond two pi normalize to [-pi, pi)', () {
      final values = <double>[
        -9 * math.pi,
        -5 * math.pi / 2,
        2 * math.pi,
        5 * math.pi / 2,
        9 * math.pi,
      ].map(NavigationYaw.normalize);

      for (final yaw in values) {
        expect(yaw, greaterThanOrEqualTo(-math.pi));
        expect(yaw, lessThan(math.pi));
      }
      expect(
        NavigationYaw.normalize(5 * math.pi / 2),
        closeTo(math.pi / 2, 1e-12),
      );
    });
  });

  group('NavigationCommandPayload', () {
    const requestedAt = 'server timestamp placeholder';

    test('SET_DOCK_POSE sends normalized radian yaw', () {
      final payload = NavigationCommandPayload.setDockPose(
        commandId: 'dock-1',
        mapVersion: 'map-v1',
        pose: Nav2Pose(x: -0.08105, y: 0.46115, yaw: -1.50554),
        requestedAt: requestedAt,
      );

      expect(payload['command'], 'SET_DOCK_POSE');
      expect(payload['yaw'], closeTo(-1.50554, 1e-12));
      expect(payload['mapVersion'], 'map-v1');
    });

    test('NAVIGATE sends normalized radian yaw', () {
      final payload = NavigationCommandPayload.navigate(
        commandId: 'navigate-1',
        mapVersion: 'map-v1',
        pose: Nav2Pose(x: 1, y: 2, yaw: 5 * math.pi / 2),
        requestedAt: requestedAt,
      );

      expect(payload['command'], 'NAVIGATE');
      expect(payload['yaw'], closeTo(math.pi / 2, 1e-12));
    });

    test('PATROL sends normalized radian yaw for every point', () {
      final payload = NavigationCommandPayload.patrol(
        commandId: 'patrol-1',
        mapVersion: 'map-v1',
        points: [
          Nav2Pose(x: 1, y: 2, yaw: 2 * math.pi),
          Nav2Pose(x: 3, y: 4, yaw: -5 * math.pi / 2),
          Nav2Pose(x: 5, y: 6, yaw: 3 * math.pi),
        ],
        requestedAt: requestedAt,
      );
      final points = payload['points']! as List<Map<String, double>>;

      expect(payload['command'], 'PATROL');
      expect(points[0]['yaw'], closeTo(0, 1e-12));
      expect(points[1]['yaw'], closeTo(-math.pi / 2, 1e-12));
      expect(points[2]['yaw'], closeTo(-math.pi, 1e-12));
    });
  });
}
