import 'package:flutter/material.dart';

import '../models/care_alarm.dart';
import '../styles/app_colors.dart';

class AlarmListCard extends StatelessWidget {
  final CareAlarm alarm;
  final VoidCallback onDone;
  final VoidCallback onGuardianNotice;
  final VoidCallback onChangeTime;

  const AlarmListCard({
    super.key,
    required this.alarm,
    required this.onDone,
    required this.onGuardianNotice,
    required this.onChangeTime,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getStatusInfo(alarm.status);

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: alarm.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              alarm.icon,
              color: alarm.color,
              size: 46,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alarm.time,
                  style: const TextStyle(
                    fontSize: 20,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  alarm.title,
                  style: const TextStyle(
                    fontSize: 30,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  alarm.description,
                  style: const TextStyle(
                    fontSize: 19,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: statusInfo.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              statusInfo.label,
              style: TextStyle(
                fontSize: 18,
                color: statusInfo.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: alarm.status == AlarmStatus.done ? null : onDone,
                icon: const Icon(Icons.check_rounded),
                label: const Text('완료'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  disabledBackgroundColor: AppColors.border,
                  minimumSize: const Size(150, 52),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onChangeTime,
                icon: const Icon(Icons.access_time_rounded),
                label: const Text('시간 변경'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                  minimumSize: const Size(150, 52),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onGuardianNotice,
                icon: const Icon(Icons.notifications_active_rounded),
                label: const Text('보호자 알림'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(
                    color: AppColors.danger,
                    width: 1.5,
                  ),
                  minimumSize: const Size(150, 52),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  AlarmStatusInfo _getStatusInfo(AlarmStatus status) {
    switch (status) {
      case AlarmStatus.waiting:
        return const AlarmStatusInfo(
          label: '예정',
          color: AppColors.primary,
        );
      case AlarmStatus.done:
        return const AlarmStatusInfo(
          label: '완료',
          color: AppColors.success,
        );
      case AlarmStatus.missed:
        return const AlarmStatusInfo(
          label: '미응답',
          color: AppColors.danger,
        );
    }
  }
}