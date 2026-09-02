import 'package:carelink/models/robot_battery_status.dart';
import 'package:carelink/widgets/robot_battery_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('배터리 값과 전압, 용량을 표시한다', (tester) async {
    await tester.pumpWidget(_app(Stream.value(RobotBatteryStatus(
      percent: 21,
      voltage: 10.817,
      capacityMah: 5200,
      updatedAt: DateTime.now(),
    ))));
    await tester.pump();

    expect(find.text('배터리 21%'), findsOneWidget);
    expect(find.text('10.82V · 용량 5200mAh'), findsOneWidget);
    expect(find.text('배터리가 부족합니다'), findsNothing);
  });

  testWidgets('20% 이하에서 부족 경고를 표시한다', (tester) async {
    await tester.pumpWidget(_app(Stream.value(RobotBatteryStatus(
      percent: 20,
      updatedAt: DateTime.now(),
    ))));
    await tester.pump();

    expect(find.text('배터리가 부족합니다'), findsOneWidget);
  });

  testWidgets('30초 지난 정보에 연결 끊김을 표시한다', (tester) async {
    await tester.pumpWidget(_app(Stream.value(RobotBatteryStatus(
      percent: 50,
      updatedAt: DateTime.now().subtract(const Duration(seconds: 31)),
    ))));
    await tester.pump();

    expect(find.text('배터리 정보 연결 끊김'), findsOneWidget);
    final opacity = tester.widget<Opacity>(find.ancestor(
      of: find.text('배터리 50%'),
      matching: find.byType(Opacity),
    ));
    expect(opacity.opacity, 0.35);
  });

  testWidgets('빈 문서를 안전하게 표시한다', (tester) async {
    await tester.pumpWidget(_app(Stream.value(const RobotBatteryStatus())));
    await tester.pump();
    expect(find.text('배터리 정보 없음'), findsOneWidget);
  });
}

Widget _app(Stream<RobotBatteryStatus> stream) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 300,
          child: RobotBatteryCard(onTap: () {}, statusStream: stream),
        ),
      ),
    );
