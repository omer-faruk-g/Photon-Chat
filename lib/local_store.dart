import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'fip.dart';

class Contact {
  final String fipId, name, code, serverUrl;
  String status;
  Contact({required this.fipId, required this.name, required this.code, required this.serverUrl, required this.status});
  Map<String, dynamic> toJson() => {'fipId': fipId, 'name': name, 'code': code, 'serverUrl': serverUrl, 'status': status};
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(fipId: j['fipId'], name: j['name'], code: j['code'], serverUrl: (j['serverUrl'] as String?) ?? '', status: j['status']);
}

class ChatMessage {
  final String from, text;
  final int ts;
  ChatMessage({required this.from, required this.text, required this.ts});
  Map<String, dynamic> toJson() => {'from': from, 'text': text, 'ts': ts};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(from: j['from'], text: j['text'], ts: j['ts']);
}

class GroupMember {
  final String fipId, name, serverUrl;
  GroupMember({required this.fipId, required this.name, required this.serverUrl});
  Map<String, dynamic> toJson() => {'fipId': fipId, 'name': name, 'serverUrl': serverUrl};
  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(fipId: j['fipId'], name: j['name'], serverUrl: (j['serverUrl'] as String?) ?? '');
}

class Group {
  final String groupId, groupCode, name, ownerFipId, ownerServerUrl;
  final bool isOwner;
  List<GroupMember> members;
  Group({required this.groupId, required this.groupCode, required this.name, required this.ownerFipId, required this.ownerServerUrl, required this.isOwner, required this.members});
  Map<String, dynamic> toJson() => {'groupId': groupId, 'groupCode': groupCode, 'name': name, 'ownerFipId': ownerFipId, 'ownerServerUrl': ownerServerUrl, 'isOwner': isOwner, 'members': members.map((m) => m.toJson()).toList()};
  factory Group.fromJson(Map<String, dynamic> j) => Group(groupId: j['groupId'], groupCode: j['groupCode'], name: j['name'], ownerFipId: j['ownerFipId'], ownerServerUrl: (j['ownerServerUrl'] as String?) ?? '', isOwner: j['isOwner'] ?? false, members: (j['members'] as List? ?? []).map((m) => GroupMember.fromJson(m as Map<String, dynamic>)).toList());
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

  static Future<List<String>> loadBlockList() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kBlockListKey);
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> blockUser(String fipId) async {
    final list = await loadBlockList();
    if (!list.contains(fipId)) { list.add(fipId); await (await SharedPreferences.getInstance()).setString(_kBlockListKey, jsonEncode(list)); }
  }

  static Future<void> unblockUser(String fipId) async {
    final list = await loadBlockList();
    list.remove(fipId);
    await (await SharedPreferences.getInstance()).setString(_kBlockListKey, jsonEncode(list));
  }

  static Future<void> wipeIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kIdentityKey, _kContactsKey, _kDisplayNameKey, _kMyServerUrlKey, _kGroupsKey, _kGuideSeenKey, _kBlockListKey]) await prefs.remove(k);
  }
}
