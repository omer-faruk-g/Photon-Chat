import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'fip.dart';

class Contact {
  final String fipId;
  final String name;
  final String code;
  final String serverUrl;
  String status;
  String avatar;
  String statusMsg;
  int lastSeen;
  Contact({required this.fipId, required this.name, required this.code, required this.serverUrl, required this.status, this.avatar = '', this.statusMsg = '', this.lastSeen = 0});
  Map<String, dynamic> toJson() => {'fipId': fipId, 'name': name, 'code': code, 'serverUrl': serverUrl, 'status': status, 'avatar': avatar, 'statusMsg': statusMsg, 'lastSeen': lastSeen};
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(fipId: j['fipId'], name: j['name'], code: j['code'], serverUrl: (j['serverUrl'] as String?) ?? '', status: j['status'], avatar: (j['avatar'] as String?) ?? '', statusMsg: (j['statusMsg'] as String?) ?? '', lastSeen: (j['lastSeen'] as int?) ?? 0);
}

class ChatMessage {
  final String from;
  final String text;
  final int ts;
  ChatMessage({required this.from, required this.text, required this.ts});
  Map<String, dynamic> toJson() => {'from': from, 'text': text, 'ts': ts};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(from: j['from'], text: j['text'], ts: j['ts']);
}

class GroupMember {
  final String fipId;
  final String name;
  final String serverUrl;
  GroupMember({required this.fipId, required this.name, required this.serverUrl});
  Map<String, dynamic> toJson() => {'fipId': fipId, 'name': name, 'serverUrl': serverUrl};
  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(fipId: j['fipId'], name: j['name'], serverUrl: (j['serverUrl'] as String?) ?? '');
}

class Group {
  final String groupId;
  final String groupCode;
  final String name;
  final String ownerFipId;
  final String ownerServerUrl;
  final bool isOwner;
  List<GroupMember> members;
  Group({required this.groupId, required this.groupCode, required this.name, required this.ownerFipId, required this.ownerServerUrl, required this.isOwner, required this.members});
  Map<String, dynamic> toJson() => {'groupId': groupId, 'groupCode': groupCode, 'name': name, 'ownerFipId': ownerFipId, 'ownerServerUrl': ownerServerUrl, 'isOwner': isOwner, 'members': members.map((m) => m.toJson()).toList()};
  factory Group.fromJson(Map<String, dynamic> j) => Group(
    groupId: j['groupId'], groupCode: j['groupCode'], name: j['name'],
    ownerFipId: j['ownerFipId'], ownerServerUrl: (j['ownerServerUrl'] as String?) ?? '',
    isOwner: j['isOwner'] ?? false,
    members: (j['members'] as List? ?? []).map((m) => GroupMember.fromJson(m as Map<String, dynamic>)).toList(),
  );
  String get address => '$groupCode@$ownerServerUrl';
}

class LocalStore {
  static const _kIdentityKey = 'knk_identity_v1';
  static const _kContactsKey = 'knk_contacts_v1';
  static const _kDisplayNameKey = 'knk_display_name_v1';
  static const _kMyServerUrlKey = 'knk_my_server_url_v1';
  static const _kGroupsKey = 'knk_groups_v1';
  static const _kGuideSeenKey = 'knk_guide_seen_v1';
  static const _kBlockListKey = 'knk_block_list_v1';
  static const _kStatusMsgKey = 'knk_status_msg_v1';
  static const _kAvatarKey = 'knk_avatar_v1';
  static const _kThemeDarkKey = 'knk_theme_dark_v1';

  static Future<String?> loadMyServerUrl() async => (await SharedPreferences.getInstance()).getString(_kMyServerUrlKey);
  static Future<void> saveMyServerUrl(String url) async => (await SharedPreferences.getInstance()).setString(_kMyServerUrlKey, url.trim());

  static Future<bool> isGuideSeen() async => (await SharedPreferences.getInstance()).getBool(_kGuideSeenKey) ?? false;
  static Future<void> markGuideSeen() async => (await SharedPreferences.getInstance()).setBool(_kGuideSeenKey, true);

  static Future<FipBlock?> loadIdentity() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kIdentityKey);
    if (raw == null) return null;
    return FipBlock.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<FipBlock> createIdentity() async {
    final fip = FipBlock.generate();
    (await SharedPreferences.getInstance()).setString(_kIdentityKey, jsonEncode(fip.toJson()));
    return fip;
  }

  static Future<String?> loadDisplayName() async => (await SharedPreferences.getInstance()).getString(_kDisplayNameKey);
  static Future<void> saveDisplayName(String name) async => (await SharedPreferences.getInstance()).setString(_kDisplayNameKey, name);

  static Future<List<Contact>> loadContacts() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kContactsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveContacts(List<Contact> contacts) async =>
      (await SharedPreferences.getInstance()).setString(_kContactsKey, jsonEncode(contacts.map((c) => c.toJson()).toList()));

  static Future<List<Group>> loadGroups() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kGroupsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveGroups(List<Group> groups) async =>
      (await SharedPreferences.getInstance()).setString(_kGroupsKey, jsonEncode(groups.map((g) => g.toJson()).toList()));

  // --- Block list ---

  static Future<List<String>> loadBlockList() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kBlockListKey);
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> saveBlockList(List<String> list) async =>
      (await SharedPreferences.getInstance()).setString(_kBlockListKey, jsonEncode(list));

  static Future<String> loadStatusMsg() async => (await SharedPreferences.getInstance()).getString(_kStatusMsgKey) ?? '';
  static Future<void> saveStatusMsg(String msg) async => (await SharedPreferences.getInstance()).setString(_kStatusMsgKey, msg);
  static Future<String> loadAvatar() async => (await SharedPreferences.getInstance()).getString(_kAvatarKey) ?? '';
  static Future<void> saveAvatar(String b64) async => (await SharedPreferences.getInstance()).setString(_kAvatarKey, b64);

  static Future<bool> loadThemeDark() async => (await SharedPreferences.getInstance()).getBool(_kThemeDarkKey) ?? true;
  static Future<void> saveThemeDark(bool isDark) async => (await SharedPreferences.getInstance()).setBool(_kThemeDarkKey, isDark);

  static Future<void> blockUser(String fipId) async {
    final list = await loadBlockList();
    if (!list.contains(fipId)) {
      list.add(fipId);
      await saveBlockList(list);
    }
  }

  static Future<void> unblockUser(String fipId) async {
    final list = await loadBlockList();
    list.remove(fipId);
    await saveBlockList(list);
  }

  static Future<int?> loadDisappearDuration(String chatKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('knk_disappear_$chatKey');
  }

  static Future<void> saveDisappearDuration(String chatKey, int? seconds) async {
    final prefs = await SharedPreferences.getInstance();
    if (seconds == null) await prefs.remove('knk_disappear_$chatKey');
    else await prefs.setInt('knk_disappear_$chatKey', seconds);
  }

  static Future<Map<String, dynamic>?> loadPinnedMessage(String chatKey) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('knk_pinned_$chatKey');
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  static Future<void> savePinnedMessage(String chatKey, Map<String, dynamic>? data) async {
    final prefs = await SharedPreferences.getInstance();
    if (data == null) await prefs.remove('knk_pinned_$chatKey');
    else await prefs.setString('knk_pinned_$chatKey', jsonEncode(data));
  }

  static Future<void> wipeIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kIdentityKey);
    await prefs.remove(_kContactsKey);
    await prefs.remove(_kDisplayNameKey);
    await prefs.remove(_kMyServerUrlKey);
    await prefs.remove(_kGroupsKey);
    await prefs.remove(_kGuideSeenKey);
    await prefs.remove(_kBlockListKey);
  }
}
