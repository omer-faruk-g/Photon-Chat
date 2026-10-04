import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class QuickReplies {
  static const _key = 'knk_quick_replies_v1';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> save(List<String> replies) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(replies));
  }

  static Future<void> add(String reply) async {
    final list = await load();
    if (!list.contains(reply)) {
      list.add(reply);
      await save(list);
    }
  }

  static Future<void> remove(String reply) async {
    final list = await load();
    list.remove(reply);
    await save(list);
  }
}
