import 'dart:io';
import 'package:flutter/services.dart';

class SoundPicker {
  static const _channel = MethodChannel('com.photonchat/sound_picker');

  static Future<List<Map<String, String>>> getNotificationSounds() async {
    if (!Platform.isAndroid) return _fallbackSounds();
    try {
      final result = await _channel.invokeMethod('getNotificationSounds');
      final list = List<Map<dynamic, dynamic>>.from(result as List);
      return list.map((m) => {'title': m['title'] as String, 'uri': m['uri'] as String}).toList();
    } catch (_) {
      return _fallbackSounds();
    }
  }

  static Future<void> playSound(String uri) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('playSound', {'uri': uri});
    } catch (_) {}
  }

  static Future<void> stopSound() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopSound');
    } catch (_) {}
  }

  static List<Map<String, String>> _fallbackSounds() => [
    {'title': 'Varsayilan', 'uri': 'default'},
    {'title': 'Sessiz', 'uri': 'silent'},
  ];
}
