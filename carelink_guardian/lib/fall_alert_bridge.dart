import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fall_event_screens.dart';

class FallAlertBridge {
  static const _channel = MethodChannel('carelink/fall_alerts');
  static bool _initialized = false;

  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFallEvent' && call.arguments is String) {
        _openDetails(navigatorKey, call.arguments as String);
      }
    });

    try {
      await _channel.invokeMethod<void>('subscribeToFallAlerts');
      await _channel.invokeMethod<void>('requestNotificationPermission');
      final eventId = await _channel.invokeMethod<String>('getInitialEventId');
      if (eventId != null && eventId.isNotEmpty) {
        _openDetails(navigatorKey, eventId);
      }
    } on PlatformException catch (error) {
      debugPrint('낙상 알림 초기화 실패: ${error.message}');
    } on MissingPluginException {
      // Android 이외 플랫폼에서는 네이티브 알림 브리지가 없다.
    }
  }

  static void _openDetails(
    GlobalKey<NavigatorState> navigatorKey,
    String eventId,
  ) {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => FallEventDetailScreen(eventId: eventId),
      ),
    );
  }
}
