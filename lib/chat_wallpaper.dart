import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatWallpaper {
  static const _keyType = 'knk_wallpaper_type_v1';
  static const _keyValue = 'knk_wallpaper_value_v1';

  static String _type = 'none';
  static String _value = '';

  static String get type => _type;
  static String get value => _value;

  static final List<Color> presetColors = [
    const Color(0xFF1B5E20),
    const Color(0xFF0D47A1),
    const Color(0xFF4A148C),
    const Color(0xFF880E4F),
    const Color(0xFF1A237E),
    const Color(0xFF004D40),
    const Color(0xFF3E2723),
    const Color(0xFF263238),
    const Color(0xFF33691E),
    const Color(0xFF01579B),
  ];

  static Future<void> loadWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    _type = prefs.getString(_keyType) ?? 'none';
    _value = prefs.getString(_keyValue) ?? '';
  }

  static Future<void> saveWallpaper(String type, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyType, type);
    await prefs.setString(_keyValue, value);
    _type = type;
    _value = value;
  }

  static Widget buildBackground() {
    if (_type == 'color' && _value.isNotEmpty) {
      final color = Color(int.parse(_value, radix: 16));
      return Positioned.fill(child: Container(color: color));
    }
    if (_type == 'image' && _value.isNotEmpty) {
      try {
        final bytes = base64Decode(_value);
        return Positioned.fill(
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    return const SizedBox.shrink();
  }
}
