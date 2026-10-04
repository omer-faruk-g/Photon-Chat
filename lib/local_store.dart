import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'e2e.dart';
import 'fip.dart';

class Contact {
  final String fipId;
  final String name;
  final String code;
  final String serverUrl;
  /// 'pending_in' | 'pending_out' | 'on'
  String status;
  /// Karşı tarafın X25519 public key'i (Base64). Bilinmiyorsa null.
  String? publicKey;
  Contact({required this.fipId, required this.name, required this.code, required this.serverUrl, required this.status, this.publicKey});
  Map<String, dynamic> toJson() => {'fipId': fipId, 'name': name, 'code': code, 'serverUrl': serverUrl, 'status': status, if (publicKey != null) 'publicKey': publicKey};
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
    fipId: j['fipId'] as String,
    name: (j['name'] as String?) ?? 'Bilinmeyen',
    code: (j['code'] as String?) ?? '?????',
    serverUrl: (j['serverUrl'] as String?) ?? '',
    status: (j['status'] as String?) ?? 'pending_out',
    publicKey: j['publicKey'] as String?,
  );
}

class ChatMessage {
  final String from;
  final String text;
  final int ts;
  ChatMessage({required this.from, required this.text, required this.ts});
  Map<String, dynamic> toJson() => {'from': from, 'text': text, 'ts': ts};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(from: j['from'] as String, text: (j['text'] as String?) ?? '', ts: (j['ts'] as num).toInt());
}

class GroupMember {
  final String fipId;
  final String name;
  final String serverUrl;
  GroupMember({required this.fipId, required this.name, required this.serverUrl});
  Map<String, dynamic> toJson() => {'fipId': fipId, 'name': name, 'serverUrl': serverUrl};
  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(fipId: j['fipId'] as String, name: (j['name'] as String?) ?? 'Bilinmeyen', serverUrl: (j['serverUrl'] as String?) ?? '');
}

class Group {
  final String groupId;
  final String groupCode;
  final String name;
  final String ownerFipId;
  final String ownerServerUrl;
  final bool isOwner;
  /// Sunucunun bu cihaza verdiği gizli grup anahtarı (sahip veya üye). Yalnızca cihazda saklanır.
  final String? token;
  List<GroupMember> members;
  Group({required this.groupId, required this.groupCode, required this.name, required this.ownerFipId, required this.ownerServerUrl, required this.isOwner, required this.members, this.token});
  Map<String, dynamic> toJson() => {'groupId': groupId, 'groupCode': groupCode, 'name': name, 'ownerFipId': ownerFipId, 'ownerServerUrl': ownerServerUrl, 'isOwner': isOwner, if (token != null) 'token': token, 'members': members.map((m) => m.toJson()).toList()};
  factory Group.fromJson(Map<String, dynamic> j) => Group(
    groupId: j['groupId'] as String, groupCode: (j['groupCode'] as String?) ?? '', name: (j['name'] as String?) ?? 'Grup',
    ownerFipId: (j['ownerFipId'] as String?) ?? '', ownerServerUrl: (j['ownerServerUrl'] as String?) ?? '',
    isOwner: (j['isOwner'] as bool?) ?? false,
    token: j['token'] as String?,
    members: (j['members'] as List? ?? []).map((m) => GroupMember.fromJson(m as Map<String, dynamic>)).toList(),
  );
  String get address => '$groupCode@$ownerServerUrl';
}

/// Bozuk tek bir kayıt tüm listeyi kaybettirmesin diye öğeleri tek tek çözer.
List<T> _decodeList<T>(String raw, T Function(Map<String, dynamic>) fromJson) {
  final List list;
  try {
    list = jsonDecode(raw) as List;
  } catch (_) {
    return [];
  }
  final out = <T>[];
  for (final e in list) {
    try {
      out.add(fromJson(Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
  }
  return out;
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
    try {
      return FipBlock.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // bozuk kayıt: uygulama çökmesin, yeni kimlik oluşturulsun
    }
  }

  static Future<FipBlock> createIdentity() async {
    final fip = FipBlock.generate();
    await saveIdentity(fip);
    return fip;
  }

  static Future<void> saveIdentity(FipBlock fip) async =>
      (await SharedPreferences.getInstance()).setString(_kIdentityKey, jsonEncode(fip.toJson()));

  static Future<String?> loadDisplayName() async => (await SharedPreferences.getInstance()).getString(_kDisplayNameKey);
  static Future<void> saveDisplayName(String name) async => (await SharedPreferences.getInstance()).setString(_kDisplayNameKey, name);

  static Future<List<Contact>> loadContacts() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kContactsKey);
    if (raw == null) return [];
    return _decodeList(raw, Contact.fromJson);
  }

  static Future<void> saveContacts(List<Contact> contacts) async =>
      (await SharedPreferences.getInstance()).setString(_kContactsKey, jsonEncode(contacts.map((c) => c.toJson()).toList()));

  static Future<List<Group>> loadGroups() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kGroupsKey);
    if (raw == null) return [];
    return _decodeList(raw, Group.fromJson);
  }

  static Future<void> saveGroups(List<Group> groups) async =>
      (await SharedPreferences.getInstance()).setString(_kGroupsKey, jsonEncode(groups.map((g) => g.toJson()).toList()));

  // --- Block list ---

  static Future<List<String>> loadBlockList() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kBlockListKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveBlockList(List<String> list) async =>
      (await SharedPreferences.getInstance()).setString(_kBlockListKey, jsonEncode(list));

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

  static Future<void> wipeIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kIdentityKey);
    await prefs.remove(_kContactsKey);
    await prefs.remove(_kDisplayNameKey);
    await prefs.remove(_kMyServerUrlKey);
    await prefs.remove(_kGroupsKey);
    await prefs.remove(_kGuideSeenKey);
    await prefs.remove(_kBlockListKey);
    await wipeE2EKeys();
  }
}
