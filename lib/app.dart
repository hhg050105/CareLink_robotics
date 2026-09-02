import 'package:flutter/material.dart';

import 'screens/assistant_idle_screen.dart';
import 'styles/app_theme.dart';

class CareLinkApp extends StatelessWidget {
  const CareLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CareLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AssistantIdleScreen(),
    );
  }
}