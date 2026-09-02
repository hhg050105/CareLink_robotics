import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'fall_alert_bridge.dart';
import 'fall_event_screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const CareLinkGuardianApp());
}

class CareLinkGuardianApp extends StatefulWidget {
  const CareLinkGuardianApp({super.key});

  @override
  State<CareLinkGuardianApp> createState() => _CareLinkGuardianAppState();
}

class _CareLinkGuardianAppState extends State<CareLinkGuardianApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FallAlertBridge.initialize(_navigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'CareLink 보호자',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F7CFF)),
      ),
      home: const GuardianHomeScreen(),
    );
  }
}

class GuardianHomeScreen extends StatelessWidget {
  const GuardianHomeScreen({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _alarmLogStream() {
    return FirebaseFirestore.instance
        .collection('care_alarm_logs')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _guardianCallStream() {
    return FirebaseFirestore.instance
        .collection('guardian_calls')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots();
  }

  Future<void> _acknowledgeGuardianCall(String docId) async {
    await FirebaseFirestore.instance
        .collection('guardian_calls')
        .doc(docId)
        .update({
          'status': 'acknowledged',
          'acknowledgedAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FallEventListScreen()),
        ),
        icon: const Icon(Icons.warning_amber_rounded),
        label: const Text('낙상 이력'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPhone = constraints.maxWidth < 600;
            final spacing = isPhone ? 16.0 : 20.0;

            return Padding(
              padding: EdgeInsets.all(isPhone ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isPhone),
                  SizedBox(height: spacing),
                  _buildStatusSummary(isPhone),
                  SizedBox(height: spacing),
                  _buildGuardianCallSection(context, isPhone),
                  SizedBox(height: spacing),
                  Text(
                    '최근 기록',
                    style: TextStyle(
                      fontSize: isPhone ? 22 : 26,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF101828),
                    ),
                  ),
                  SizedBox(height: isPhone ? 10 : 14),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _alarmLogStream(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              '기록을 불러오지 못했습니다.',
                              style: TextStyle(fontSize: 20),
                            ),
                          );
                        }

                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              '아직 기록이 없습니다.',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF667085),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: isPhone ? 10 : 14),
                          itemBuilder: (context, index) {
                            final data = docs[index].data();

                            return GuardianLogCard(
                              title: data['title']?.toString() ?? '알 수 없음',
                              description:
                                  data['description']?.toString() ?? '',
                              time: data['time']?.toString() ?? '-',
                              status: data['status']?.toString() ?? '-',
                              device: data['device']?.toString() ?? '-',
                              createdAt: data['createdAt'],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isPhone) {
    return Row(
      children: [
        Container(
          width: isPhone ? 54 : 74,
          height: isPhone ? 54 : 74,
          decoration: BoxDecoration(
            color: const Color(0xFF4F7CFF),
            borderRadius: BorderRadius.circular(isPhone ? 18 : 24),
          ),
          child: Icon(
            Icons.family_restroom_rounded,
            color: Colors.white,
            size: isPhone ? 30 : 42,
          ),
        ),
        SizedBox(width: isPhone ? 12 : 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CareLink 보호자',
                style: TextStyle(
                  fontSize: isPhone ? 24 : 32,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '어르신의 식사와 복약 상태를 확인합니다',
                style: TextStyle(
                  fontSize: isPhone ? 14 : 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF667085),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSummary(bool isPhone) {
    return Row(
      children: [
        Expanded(
          child: GuardianSummaryCard(
            title: '연결 상태',
            value: '정상',
            icon: Icons.wifi_rounded,
            color: const Color(0xFF12B76A),
            compact: isPhone,
          ),
        ),
        SizedBox(width: isPhone ? 8 : 14),
        Expanded(
          child: GuardianSummaryCard(
            title: '확인 대상',
            value: 'elder_001',
            icon: Icons.person_rounded,
            color: const Color(0xFF4F7CFF),
            compact: isPhone,
          ),
        ),
        SizedBox(width: isPhone ? 8 : 14),
        Expanded(
          child: GuardianSummaryCard(
            title: '알림 종류',
            value: '식사 · 복약',
            icon: Icons.notifications_active_rounded,
            color: const Color(0xFFF79009),
            compact: isPhone,
          ),
        ),
      ],
    );
  }

  Widget _buildGuardianCallSection(BuildContext context, bool isPhone) {
    return SizedBox(
      height: isPhone ? 190 : 210,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _guardianCallStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                    ),
                    child: const Center(
                      child: Text(
                        '보호자 호출 기록을 불러오지 못했습니다.',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                    ),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF12B76A),
                          size: 42,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            '현재 보호자 호출 기록이 없습니다.',
                            style: TextStyle(
                              fontSize: isPhone ? 17 : 22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF344054),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();

                    return GuardianCallCard(
                      docId: doc.id,
                      title: data['title']?.toString() ?? '보호자 호출',
                      message: data['message']?.toString() ?? '',
                      status: data['status']?.toString() ?? 'pending',
                      createdAt: data['createdAt'],
                      compact: isPhone,
                      width: isPhone ? constraints.maxWidth : 430,
                      onAcknowledge: () async {
                        await _acknowledgeGuardianCall(doc.id);
                      },
                    );
                  },
                );
              },
            ),
      ),
    );
  }
}

class GuardianSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;

  const GuardianSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 118 : null,
      padding: EdgeInsets.all(compact ? 10 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF101828),
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 21,
                          color: Color(0xFF101828),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class GuardianLogCard extends StatelessWidget {
  final String title;
  final String description;
  final String time;
  final String status;
  final String device;
  final Object? createdAt;

  const GuardianLogCard({
    super.key,
    required this.title,
    required this.description,
    required this.time,
    required this.status,
    required this.device,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDone = status == 'done';
    final statusColor = isDone
        ? const Color(0xFF12B76A)
        : const Color(0xFFE11D48);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final statusChip = Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 18,
            vertical: compact ? 7 : 12,
          ),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
          ),
          child: Text(
            isDone ? '완료' : status,
            style: TextStyle(
              fontSize: compact ? 13 : 18,
              fontWeight: FontWeight.w900,
              color: statusColor,
            ),
          ),
        );
        final eventIcon = Container(
          width: compact ? 48 : 66,
          height: compact ? 48 : 66,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(compact ? 16 : 22),
          ),
          child: Icon(
            isDone ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: statusColor,
            size: compact ? 28 : 38,
          ),
        );

        return Container(
          padding: EdgeInsets.all(compact ? 14 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(compact ? 18 : 24),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        eventIcon,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$title · $time',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF101828),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        statusChip,
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '기기: $device',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF98A2B3),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    eventIcon,
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$title · $time',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF101828),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF667085),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '기기: $device',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF98A2B3),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    statusChip,
                  ],
                ),
        );
      },
    );
  }
}

class GuardianCallCard extends StatelessWidget {
  final String docId;
  final String title;
  final String message;
  final String status;
  final Object? createdAt;
  final VoidCallback onAcknowledge;
  final bool compact;
  final double width;

  const GuardianCallCard({
    super.key,
    required this.docId,
    required this.title,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.onAcknowledge,
    this.compact = false,
    this.width = 430,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPending = status == 'pending';

    return Container(
      width: width,
      padding: EdgeInsets.all(compact ? 14 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 20 : 26),
        border: Border.all(
          color: isPending ? const Color(0xFFE11D48) : const Color(0xFFE4E7EC),
          width: isPending ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isPending
                ? const Color(0xFFE11D48).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isPending
                            ? const Color(0xFFE11D48).withValues(alpha: 0.12)
                            : const Color(0xFF12B76A).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        isPending
                            ? Icons.notifications_active_rounded
                            : Icons.check_circle_rounded,
                        color: isPending
                            ? const Color(0xFFE11D48)
                            : const Color(0xFF12B76A),
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPending ? '긴급 보호자 호출' : '확인 완료',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isPending
                                  ? const Color(0xFFE11D48)
                                  : const Color(0xFF12B76A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '발생 시간: ${_formatTimestamp(createdAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF98A2B3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  message.isEmpty ? '어르신이 보호자 호출 버튼을 눌렀습니다.' : message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF344054),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isPending ? onAcknowledge : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE11D48),
                      disabledBackgroundColor: const Color(0xFFE4E7EC),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: Text(
                      isPending ? '확인' : '완료',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: isPending
                        ? const Color(0xFFE11D48).withValues(alpha: 0.12)
                        : const Color(0xFF12B76A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    isPending
                        ? Icons.notifications_active_rounded
                        : Icons.check_circle_rounded,
                    color: isPending
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF12B76A),
                    size: 38,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPending ? '긴급 보호자 호출' : '확인 완료',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: isPending
                              ? const Color(0xFFE11D48)
                              : const Color(0xFF12B76A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message.isEmpty ? '어르신이 보호자 호출 버튼을 눌렀습니다.' : message,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF344054),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '발생 시간: ${_formatTimestamp(createdAt)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF98A2B3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                FilledButton(
                  onPressed: isPending ? onAcknowledge : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    disabledBackgroundColor: const Color(0xFFE4E7EC),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                  ),
                  child: Text(
                    isPending ? '확인' : '완료',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatTimestamp(Object? value) {
    if (value is Timestamp) {
      final date = value.toDate();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    return '-';
  }
}
