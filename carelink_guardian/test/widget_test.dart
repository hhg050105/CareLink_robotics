import 'package:carelink_guardian/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guardian cards fit a phone-width layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Row(
                children: [
                  Expanded(
                    child: GuardianSummaryCard(
                      title: '연결 상태',
                      value: '정상',
                      icon: Icons.wifi_rounded,
                      color: Colors.green,
                      compact: true,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: GuardianSummaryCard(
                      title: '확인 대상',
                      value: 'elder_001',
                      icon: Icons.person_rounded,
                      color: Colors.blue,
                      compact: true,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: GuardianSummaryCard(
                      title: '알림 종류',
                      value: '식사 · 복약',
                      icon: Icons.notifications_rounded,
                      color: Colors.orange,
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const GuardianLogCard(
                title: '복약 알림',
                description: '복약 확인이 필요합니다.',
                time: '09:00',
                status: 'pending',
                device: 'elder_001',
                createdAt: null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 190,
                child: GuardianCallCard(
                  docId: 'test',
                  title: '보호자 호출',
                  message: '어르신이 보호자 호출 버튼을 눌렀습니다.',
                  status: 'pending',
                  createdAt: null,
                  compact: true,
                  width: 380,
                  onAcknowledge: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('CareLink 보호자'), findsNothing);
    expect(find.text('식사 · 복약'), findsOneWidget);
    expect(find.text('복약 알림 · 09:00'), findsOneWidget);
    expect(find.text('긴급 보호자 호출'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
