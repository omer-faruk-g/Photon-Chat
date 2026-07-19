import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLock {
  static const _enabledKey = 'knk_app_lock_enabled_v1';
  static const _typeKey = 'knk_app_lock_type_v1'; // 'pin' or 'pattern'
  static const _hashKey = 'knk_app_lock_hash_v1';
  static const _pinLenKey = 'knk_app_lock_pinlen_v1';

  static Future<int> getPinLength() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pinLenKey) ?? 4;
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<String> getType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_typeKey) ?? 'pin';
  }

  static Future<void> enable(String type, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    await prefs.setString(_typeKey, type);
    await prefs.setString(_hashKey, _hash(value));
    if (type == 'pin') await prefs.setInt(_pinLenKey, value.length);
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.remove(_hashKey);
  }

  static Future<bool> verify(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_hashKey);
    if (stored == null) return false;
    return stored == _hash(value);
  }

  static String _hash(String value) {
    return sha256.convert(utf8.encode('photon_lock_$value')).toString();
  }
}
