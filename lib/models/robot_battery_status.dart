import 'package:cloud_firestore/cloud_firestore.dart';

class RobotBatteryStatus {
  const RobotBatteryStatus({
    this.voltage,
    this.percent,
    this.capacityMah,
    this.cellCount,
    this.updatedAt,
  });

  final double? voltage;
  final int? percent;
  final int? capacityMah;
  final int? cellCount;
  final DateTime? updatedAt;

  factory RobotBatteryStatus.fromFirestore(Map<String, dynamic>? data) {
    final rawPercent = data?['batteryPercent'];
    final rawVoltage = data?['batteryVoltage'];
    final rawCapacity = data?['batteryCapacityMah'];
    final rawCellCount = data?['batteryCellCount'];
    final rawUpdatedAt = data?['batteryUpdatedAt'];

    return RobotBatteryStatus(
      voltage: rawVoltage is num ? rawVoltage.toDouble() : null,
      percent: rawPercent is num
          ? rawPercent.round().clamp(0, 100).toInt()
          : null,
      capacityMah: rawCapacity is num ? rawCapacity.round() : null,
      cellCount: rawCellCount is num ? rawCellCount.round() : null,
      updatedAt: switch (rawUpdatedAt) {
        Timestamp timestamp => timestamp.toDate(),
        DateTime dateTime => dateTime,
        _ => null,
      },
    );
  }

  bool isStaleAt(DateTime now) {
    final lastUpdatedAt = updatedAt;
    return lastUpdatedAt != null &&
        now.difference(lastUpdatedAt) >= const Duration(seconds: 30);
  }
}
