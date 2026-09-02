import 'dart:async';

import 'package:flutter/material.dart';

import '../models/care_alarm.dart';
import '../styles/app_colors.dart';
import '../styles/app_text_styles.dart';
import '../widgets/alarm_list_card.dart';
import '../widgets/alarm_summary_card.dart';
import 'assistant_idle_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  Timer? _idleTimer;

  final List<CareAlarm> _alarms = [
    CareAlarm(
      time: '오전 08:00',
      title: '아침 약',
      description: '식사 후 아침 약을 복용해주세요',
      icon: Icons.medication_rounded,
      color: AppColors.primary,
      status: AlarmStatus.waiting,
    ),
    CareAlarm(
      time: '오후 12:00',
      title: '점심 식사',
      description: '점심 식사 시간을 확인해주세요',
      icon: Icons.restaurant_rounded,
      color: AppColors.warning,
      status: AlarmStatus.waiting,
    ),
    CareAlarm(
      time: '오후 06:00',
      title: '저녁 약',
      description: '저녁 약 복용 여부를 확인해주세요',
      icon: Icons.medication_liquid_rounded,
      color: AppColors.success,
      status: AlarmStatus.waiting,
    ),
    CareAlarm(
      time: '오후 09:00',
      title: '취침 확인',
      description: '주무시기 전 상태를 확인해주세요',
      icon: Icons.bedtime_rounded,
      color: AppColors.purple,
      status: AlarmStatus.waiting,
    ),
  ];

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

    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const AssistantIdleScreen(),
        ),
        (route) => false,
      );
    });
  }

  void _resetIdleTimer() {
    _startIdleTimer();
  }

Future<void> _markDone(int index) async {
  _resetIdleTimer();

  setState(() {
    _alarms[index].status = AlarmStatus.done;
  });

  final now = DateTime.now();
  final tomorrowMidnight = DateTime(now.year, now.month, now.day + 1);

  await FirebaseFirestore.instance.collection('care_alarm_logs').add({
    'elderId': 'elder_001',
    'title': _alarms[index].title,
    'description': _alarms[index].description,
    'time': _alarms[index].time,
    'status': 'done',
    'device': 'galaxy_tab',
    'createdAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(tomorrowMidnight),
  });

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${_alarms[index].title} 완료 기록이 저장되었습니다.'),
      duration: const Duration(seconds: 2),
    ),
  );
}

  void _markGuardianNotice(int index) {
    _resetIdleTimer();

    setState(() {
      _alarms[index].status = AlarmStatus.missed;
    });

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            '보호자 알림 준비',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            '${_alarms[index].title} 알림을 보호자에게 전송하는 기능은 Firebase 연결 후 작동합니다.',
            style: const TextStyle(fontSize: 20),
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

  Future<void> _changeAlarmTime(int index) async {
    _resetIdleTimer();

    final TimeOfDay initialTime = _parseTimeLabel(_alarms[index].time);

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: '${_alarms[index].title} 시간 선택',
      confirmText: '확인',
      cancelText: '취소',
      hourLabelText: '시',
      minuteLabelText: '분',
    );

    if (pickedTime == null) {
      _resetIdleTimer();
      return;
    }

    setState(() {
      _alarms[index].time = _formatKoreanTime(pickedTime);
      _alarms[index].status = AlarmStatus.waiting;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_alarms[index].title} 시간이 ${_alarms[index].time}으로 변경되었습니다.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    _resetIdleTimer();
  }

  TimeOfDay _parseTimeLabel(String timeLabel) {
    final bool isPm = timeLabel.contains('오후');

    final RegExp regex = RegExp(r'(\d{1,2}):(\d{2})');
    final Match? match = regex.firstMatch(timeLabel);

    if (match == null) {
      return const TimeOfDay(hour: 8, minute: 0);
    }

    int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);

    if (isPm && hour != 12) {
      hour += 12;
    }

    if (!isPm && hour == 12) {
      hour = 0;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatKoreanTime(TimeOfDay time) {
    final bool isAm = time.hour < 12;
    final String period = isAm ? '오전' : '오후';

    int displayHour = time.hourOfPeriod;

    if (displayHour == 0) {
      displayHour = 12;
    }

    final String hourText = displayHour.toString().padLeft(2, '0');
    final String minuteText = time.minute.toString().padLeft(2, '0');

    return '$period $hourText:$minuteText';
  }

  void _resetAllAlarms() {
    _resetIdleTimer();

    setState(() {
      for (final alarm in _alarms) {
        alarm.status = AlarmStatus.waiting;
      }
    });
  }

  int get _doneCount {
    return _alarms.where((alarm) => alarm.status == AlarmStatus.done).length;
  }

  int get _missedCount {
    return _alarms.where((alarm) => alarm.status == AlarmStatus.missed).length;
  }

  int get _waitingCount {
    return _alarms.where((alarm) => alarm.status == AlarmStatus.waiting).length;
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
                _buildHeader(),
                const SizedBox(height: 24),
                _buildSummaryCards(),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.separated(
                    itemCount: _alarms.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 18),
                    itemBuilder: (context, index) {
                      return AlarmListCard(
                        alarm: _alarms[index],
                        onDone: () => _markDone(index),
                        onGuardianNotice: () => _markGuardianNotice(index),
                        onChangeTime: () => _changeAlarmTime(index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: () {
            _idleTimer?.cancel();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('뒤로'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 18,
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 20),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '오늘의 알람',
                style: AppTextStyles.screenTitle,
              ),
              SizedBox(height: 6),
              Text(
                '복약, 식사, 취침 확인 시간을 조절할 수 있습니다',
                style: AppTextStyles.screenSubtitle,
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _resetAllAlarms,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('초기화'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 18,
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: AlarmSummaryCard(
            title: '예정',
            count: _waitingCount,
            color: AppColors.primary,
            icon: Icons.schedule_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AlarmSummaryCard(
            title: '완료',
            count: _doneCount,
            color: AppColors.success,
            icon: Icons.check_circle_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AlarmSummaryCard(
            title: '미응답',
            count: _missedCount,
            color: AppColors.danger,
            icon: Icons.warning_rounded,
          ),
        ),
      ],
    );
  }
}