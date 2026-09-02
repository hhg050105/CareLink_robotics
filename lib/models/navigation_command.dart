import 'dart:math' as math;

/// ROS map yaw helpers.
///
/// Screen coordinates grow downwards on Y, while ROS map coordinates grow
/// upwards. All values returned by this class are radians in [-pi, pi).
abstract final class NavigationYaw {
  static double normalize(double yaw) {
    if (!yaw.isFinite) {
      throw ArgumentError.value(yaw, 'yaw', 'must be finite');
    }
    return (yaw + math.pi) % (2 * math.pi) - math.pi;
  }

  static double fromScreenVector(double dx, double dy) {
    if (!dx.isFinite || !dy.isFinite || (dx == 0 && dy == 0)) {
      throw ArgumentError(
        'Screen direction vector must be finite and non-zero.',
      );
    }
    return normalize(math.atan2(-dy, dx));
  }

  static double fromScreenClockwiseAngle(double screenAngle) =>
      normalize(-screenAngle);

  static double betweenWorldPoints({
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
  }) {
    final dx = toX - fromX;
    final dy = toY - fromY;
    if (!dx.isFinite || !dy.isFinite || (dx == 0 && dy == 0)) {
      throw ArgumentError(
        'World direction points must be finite and distinct.',
      );
    }
    return normalize(math.atan2(dy, dx));
  }
}

class Nav2Pose {
  Nav2Pose({required this.x, required this.y, required double yaw})
    : yaw = NavigationYaw.normalize(yaw) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Nav2 pose coordinates must be finite.');
    }
  }

  final double x;
  final double y;
  final double yaw;

  Map<String, double> toPayload() => {'x': x, 'y': y, 'yaw': yaw};
}

/// Builds navigation documents without changing the existing Firestore
/// commandId/status/mapVersion protocol.
abstract final class NavigationCommandPayload {
  static Map<String, Object?> setDockPose({
    required String commandId,
    required String mapVersion,
    required Nav2Pose pose,
    required Object requestedAt,
  }) => {
    'command': 'SET_DOCK_POSE',
    'commandId': commandId,
    'status': 'REQUESTED',
    ...pose.toPayload(),
    'mapVersion': mapVersion,
    'requestedAt': requestedAt,
  };

  static Map<String, Object?> navigate({
    required String commandId,
    required String mapVersion,
    required Nav2Pose pose,
    required Object requestedAt,
  }) => {
    'command': 'NAVIGATE',
    'commandId': commandId,
    'status': 'REQUESTED',
    ...pose.toPayload(),
    'mapVersion': mapVersion,
    'requestedAt': requestedAt,
  };

  static Map<String, Object?> patrol({
    required String commandId,
    required String mapVersion,
    required List<Nav2Pose> points,
    required Object requestedAt,
  }) => {
    'command': 'PATROL',
    'commandId': commandId,
    'status': 'REQUESTED',
    'mapVersion': mapVersion,
    'points': points.map((point) => point.toPayload()).toList(growable: false),
    'requestedAt': requestedAt,
  };
}
