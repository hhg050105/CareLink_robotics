import 'package:flutter/material.dart';

enum AlarmStatus {
  waiting,
  done,
  missed,
}

class CareAlarm {
  String time;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  AlarmStatus status;

  CareAlarm({
    required this.time,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.status,
  });
}

class AlarmStatusInfo {
  final String label;
  final Color color;

  const AlarmStatusInfo({
    required this.label,
    required this.color,
  });
}