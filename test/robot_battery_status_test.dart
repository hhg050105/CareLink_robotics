import 'package:carelink/models/robot_battery_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RobotBatteryStatus', () {
    test('숫자 변환과 퍼센트 범위 제한', () {
      final high = RobotBatteryStatus.fromFirestore({
        'batteryVoltage': 10.817,
        'batteryPercent': 120,
        'batteryCapacityMah': 5200,
        'batteryCellCount': 3,
      });
      final low = RobotBatteryStatus.fromFirestore({'batteryPercent': -1});

      expect(high.voltage, 10.817);
      expect(high.percent, 100);
      expect(high.capacityMah, 5200);
      expect(high.cellCount, 3);
      expect(low.percent, 0);
    });

    test('Timestamp 변환', () {
      final date = DateTime(2026, 9, 1, 12);
      final status = RobotBatteryStatus.fromFirestore({
        'batteryUpdatedAt': Timestamp.fromDate(date),
      });
      expect(status.updatedAt, date);
    });

    test('문서, 필드, 타입 누락을 안전하게 처리', () {
      final missing = RobotBatteryStatus.fromFirestore(null);
      final invalid = RobotBatteryStatus.fromFirestore({
        'batteryVoltage': 'unknown',
        'batteryPercent': null,
        'batteryUpdatedAt': 'yesterday',
      });
      expect(missing.percent, isNull);
      expect(missing.isStaleAt(DateTime.now()), isFalse);
      expect(invalid.voltage, isNull);
      expect(invalid.updatedAt, isNull);
    });

    test('30초부터 연결 끊김으로 판단', () {
      final updatedAt = DateTime(2026, 9, 1, 12);
      final status = RobotBatteryStatus(updatedAt: updatedAt);
      expect(status.isStaleAt(updatedAt.add(const Duration(seconds: 29))), isFalse);
      expect(status.isStaleAt(updatedAt.add(const Duration(seconds: 30))), isTrue);
    });
  });
}
