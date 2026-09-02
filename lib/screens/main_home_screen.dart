import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../styles/app_colors.dart';
import '../styles/app_text_styles.dart';
import '../widgets/home_menu_card.dart';
import '../widgets/robot_battery_card.dart';
import 'alarm_screen.dart';
import 'admin_settings_screen.dart';
import 'assistant_idle_screen.dart';
import 'person_follower_screen.dart';

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _startIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();

    _idleTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      _goIdle();
    });
  }

  void _resetIdleTimer() {
    _startIdleTimer();
  }

  void _goIdle() {
    _idleTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AssistantIdleScreen()),
    );
  }

  Future<void> _openAlarmScreen() async {
    _idleTimer?.cancel();

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlarmScreen()),
    );

    if (!mounted) return;
    _startIdleTimer();
  }

  Future<void> _openPersonFollowerScreen() async {
    _idleTimer?.cancel();

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PersonFollowerScreen()),
    );

    if (!mounted) return;
    _startIdleTimer();
  }

  Future<void> _openAdminSettings() async {
    _idleTimer?.cancel();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
    );
    if (mounted) _startIdleTimer();
  }

  Future<void> _sendGuardianCall() async {
    _resetIdleTimer();

    final now = DateTime.now();
    final tomorrowMidnight = DateTime(now.year, now.month, now.day + 1);

    try {
      await FirebaseFirestore.instance.collection('guardian_calls').add({
        'elderId': 'elder_001',
        'type': 'guardian_call',
        'title': '보호자 호출',
        'message': '어르신이 보호자 호출 버튼을 눌렀습니다.',
        'status': 'pending',
        'device': 'galaxy_tab',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(tomorrowMidnight),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('보호자에게 호출 알림을 보냈습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text(
              '호출 전송 실패',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            content: Text(
              'Firebase 저장 중 문제가 발생했습니다.\n\n$e',
              style: const TextStyle(fontSize: 18),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _resetIdleTimer();
                },
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    }
  }

  void _showPreparingDialog(String title) {
    _resetIdleTimer();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            '다음 단계에서 실제 기능을 연결할 예정입니다.',
            style: TextStyle(fontSize: 20),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _resetIdleTimer();
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  void _showGuardianCallDialog() {
    _resetIdleTimer();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            '보호자 호출',
            style: TextStyle(
              color: AppColors.danger,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: const Text(
            '보호자에게 긴급 호출 알림을 보내시겠습니까?',
            style: TextStyle(fontSize: 22),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _resetIdleTimer();
              },
              child: const Text('취소', style: TextStyle(fontSize: 18)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () async {
                Navigator.pop(context);
                await _sendGuardianCall();
              },
              child: const Text('호출하기', style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _resetIdleTimer,
      onPanDown: (_) => _resetIdleTimer(),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopArea(),
                const SizedBox(height: 26),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: HomeMenuCard(
                                title: '알람',
                                subtitle: '복약 · 식사 · 일정 관리',
                                icon: Icons.alarm_rounded,
                                color: AppColors.primary,
                                onTap: _openAlarmScreen,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: HomeMenuCard(
                                title: '보호자 호출',
                                subtitle: '긴급 상황 알림 전송',
                                icon: Icons.call_rounded,
                                color: AppColors.danger,
                                onTap: _showGuardianCallDialog,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: HomeMenuCard(
                                title: '사람 추종',
                                subtitle: '시작 · 정지 · 현재 상태 확인',
                                icon: Icons.directions_walk_rounded,
                                color: AppColors.success,
                                onTap: _openPersonFollowerScreen,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: RobotBatteryCard(
                                onTap: () => _showPreparingDialog('로봇 상태'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopArea() {
    return Row(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 44),
        ),
        const SizedBox(width: 20),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CareLink 돌봄 비서', style: AppTextStyles.homeTitle),
              SizedBox(height: 6),
              Text('필요한 기능을 선택해주세요', style: AppTextStyles.homeSubtitle),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: '관리자 설정',
          onPressed: _openAdminSettings,
          icon: const Icon(Icons.admin_panel_settings_rounded),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _goIdle,
          icon: const Icon(Icons.nightlight_round),
          label: const Text('대기화면'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
