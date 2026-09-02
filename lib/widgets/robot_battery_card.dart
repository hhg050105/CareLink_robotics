import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/robot_battery_status.dart';
import '../styles/app_colors.dart';
import '../styles/app_text_styles.dart';

class RobotBatteryCard extends StatefulWidget {
  const RobotBatteryCard({
    super.key,
    required this.onTap,
    this.statusStream,
  });

  final VoidCallback onTap;
  final Stream<RobotBatteryStatus>? statusStream;

  @override
  State<RobotBatteryCard> createState() => _RobotBatteryCardState();
}

class _RobotBatteryCardState extends State<RobotBatteryCard> {
  StreamSubscription<RobotBatteryStatus>? _subscription;
  Timer? _freshnessTimer;
  RobotBatteryStatus? _status;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final stream = widget.statusStream ??
        FirebaseFirestore.instance
            .collection('robot_status')
            .doc('main')
            .snapshots()
            .map((snapshot) => RobotBatteryStatus.fromFirestore(snapshot.data()));
    _subscription = stream.listen(_handleStatus, onError: _handleError);
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status?.updatedAt != null) setState(() {});
    });
  }

  void _handleStatus(RobotBatteryStatus status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _isLoading = false;
      _error = null;
    });
  }

  void _handleError(Object _) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _error = '배터리 정보를 불러오지 못했습니다';
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  IconData _batteryIcon(int? percent) {
    if (percent == null) return Icons.battery_unknown_rounded;
    if (percent <= 20) return Icons.battery_1_bar_rounded;
    if (percent <= 50) return Icons.battery_3_bar_rounded;
    if (percent <= 80) return Icons.battery_5_bar_rounded;
    return Icons.battery_full_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final percent = status?.percent;
    final isLow = percent != null && percent <= 20;
    final isStale = status?.isStaleAt(DateTime.now()) ?? false;
    final color = isLow ? AppColors.danger : AppColors.success;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  children: [
                    Opacity(
                      opacity: isStale ? 0.35 : 1,
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Icon(_batteryIcon(percent), color: color, size: 48),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('로봇 상태', style: AppTextStyles.cardTitle),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: isStale ? 0.35 : 1,
                            child: Text(
                              percent == null ? '배터리 정보 없음' : '배터리 $percent%',
                              style: AppTextStyles.cardSubtitle.copyWith(color: color),
                            ),
                          ),
                          if (status?.voltage != null || status?.capacityMah != null)
                            Opacity(
                              opacity: isStale ? 0.35 : 1,
                              child: Text(
                                [
                                  if (status?.voltage != null)
                                    '${status!.voltage!.toStringAsFixed(2)}V',
                                  if (status?.capacityMah != null)
                                    '용량 ${status!.capacityMah}mAh',
                                ].join(' · '),
                                style: AppTextStyles.cardSubtitle.copyWith(fontSize: 16),
                              ),
                            ),
                          if (isLow)
                            const Text(
                              '배터리가 부족합니다',
                              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800),
                            ),
                          if (isStale)
                            const Text(
                              '배터리 정보 연결 끊김',
                              style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800),
                            ),
                          if (_error != null)
                            Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
