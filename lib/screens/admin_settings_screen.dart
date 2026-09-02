import 'package:flutter/material.dart';

import 'dock_pose_setup_screen.dart';

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('관리자 설정')),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(20),
              leading: const Icon(Icons.ev_station_rounded, size: 42),
              title: const Text('충전 도크 위치 설정'),
              subtitle: const Text('도크에 결합된 로봇의 위치와 정면 방향을 한 번 지정합니다.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DockPoseSetupScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
