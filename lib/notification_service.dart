import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  // Dedupe: title+body -> last shown ts. Suppress identical notifs within window.
  static final Map<String, int> _recent = {};
  static const int _dedupeWindowMs = 30 * 1000;

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
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '$title|$body';
    final last = _recent[key];
    if (last != null && (now - last) < _dedupeWindowMs) return;
    _recent[key] = now;
    // Garbage-collect stale keys so the map doesn't grow forever.
    if (_recent.length > 64) {
      _recent.removeWhere((_, ts) => (now - ts) > _dedupeWindowMs);
    }
    final prefs = await SharedPreferences.getInstance();
    final soundUri = prefs.getString('knk_notif_sound_uri_v1') ?? 'default';
    final soundTitle = prefs.getString('knk_notif_sound_v1') ?? 'Varsayilan';
    final isSilent = soundUri == 'silent' || soundTitle == 'Sessiz';
    final isDefault = soundUri == 'default' || soundTitle == 'Varsayilan';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        // Use a collision-free channel id per sound URI (hashCode collides).
        'photon_chat_notifs_${sha1.convert(utf8.encode(soundUri)).toString().substring(0, 12)}',
        'Photon Chat',
        channelDescription: 'Photon Chat bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        playSound: !isSilent,
        sound: (!isSilent && !isDefault) ? UriAndroidNotificationSound(soundUri) : null,
        enableVibration: !isSilent,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title, body, details,
    );
  }
}
