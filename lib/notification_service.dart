import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  static Future<void> show(String title, String body) async {
    if (!Platform.isAndroid) return;
    if (!_initialized) await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'photon_chat_notifs',
        'Photon Chat',
        channelDescription: 'Photon Chat bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title, body, details,
    );
  }
}
