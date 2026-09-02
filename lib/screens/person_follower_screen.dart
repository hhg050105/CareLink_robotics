import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/person_follower_mode.dart';
import '../styles/app_colors.dart';
import '../styles/app_text_styles.dart';
import 'patrol_map_preview_screen.dart';

class PersonFollowerScreen extends StatefulWidget {
  const PersonFollowerScreen({super.key});

  @override
  State<PersonFollowerScreen> createState() => _PersonFollowerScreenState();
}

class _PersonFollowerScreenState extends State<PersonFollowerScreen> {
  static const String _requesterId = 'carelink-tablet';

  final DocumentReference<Map<String, dynamic>> _controlDocument =
      FirebaseFirestore.instance.doc(
        'robots/carelink-01/control/personFollower',
      );

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  PersonFollowerMode _mode = PersonFollowerMode.stop;
  bool _isSaving = false;
  bool _isLoading = true;
  String? _streamError;

  @override
  void initState() {
    super.initState();
    _subscription = _controlDocument.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _mode = PersonFollowerMode.fromFirestore(snapshot.data()?['mode']);
          _isLoading = false;
          _streamError = null;
        });
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _mode = PersonFollowerMode.stop;
          _isLoading = false;
          _streamError = '현재 로봇 상태를 불러오지 못했습니다.';
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _setMode(PersonFollowerMode requestedMode) async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      await _controlDocument.set({
        'mode': requestedMode.firestoreValue,
        'requestedAt': FieldValue.serverTimestamp(),
        'requestedBy': _requesterId,
      }, SetOptions(merge: true));

      if (!mounted) return;
      final message = requestedMode == PersonFollowerMode.follow
          ? '사람 추종을 시작합니다.'
          : '로봇을 정지합니다.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('명령 전송에 실패했습니다. 네트워크를 확인해 주세요.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showPatrolPreparing() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PatrolMapPreviewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFollowing = _mode == PersonFollowerMode.follow;
    final statusText = _isSaving ? '모드 변경 중' : (isFollowing ? '사람 추종 중' : '정지');
    final statusColor = _isSaving
        ? AppColors.warning
        : (isFollowing ? AppColors.success : AppColors.textSecondary);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
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
                        Text('로봇 운행 모드', style: AppTextStyles.screenTitle),
                        SizedBox(height: 6),
                        Text(
                          '정지, 사람 추종, 순찰 모드를 선택합니다.',
                          style: AppTextStyles.screenSubtitle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(34),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoading)
                        const CircularProgressIndicator()
                      else ...[
                        Icon(
                          isFollowing
                              ? Icons.directions_walk_rounded
                              : Icons.smart_toy_rounded,
                          size: 82,
                          color: statusColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                          ),
                        ),
                      ],
                      if (_streamError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _streamError!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 17,
                          ),
                        ),
                      ],
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          Expanded(
                            child: _modeButton(
                              label: '정지',
                              icon: Icons.stop_rounded,
                              color: AppColors.danger,
                              onPressed: () =>
                                  _setMode(PersonFollowerMode.stop),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _modeButton(
                              label: '사람 추종',
                              icon: Icons.directions_walk_rounded,
                              color: AppColors.success,
                              onPressed: () =>
                                  _setMode(PersonFollowerMode.follow),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _modeButton(
                              label: '순찰',
                              icon: Icons.route_rounded,
                              color: AppColors.purple,
                              onPressed: _showPatrolPreparing,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '지도에서 3개 지점을 선택해 실제 순찰을 시작할 수 있습니다.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_isSaving) ...[
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: _isSaving ? null : onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 22),
        textStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
      ),
    );
  }
}
