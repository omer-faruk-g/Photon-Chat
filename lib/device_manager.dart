import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class LinkedDevice {
  final String deviceId;
  final String fipId;
  final String name;
  final int linkedAt;
  bool isFake;
  bool isBanned;
  bool isMod;
  List<DeviceActivity> activities;

  LinkedDevice({
    required this.deviceId,
    required this.fipId,
    required this.name,
    required this.linkedAt,
    this.isFake = false,
    this.isBanned = false,
    this.isMod = false,
    List<DeviceActivity>? activities,
  }) : activities = activities ?? [];

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'fipId': fipId,
    'name': name,
    'linkedAt': linkedAt,
    'isFake': isFake,
    'isBanned': isBanned,
    'isMod': isMod,
    'activities': activities.map((a) => a.toJson()).toList(),
  };

  factory LinkedDevice.fromJson(Map<String, dynamic> j) => LinkedDevice(
    deviceId: j['deviceId'] ?? '',
    fipId: j['fipId'] ?? '',
    name: j['name'] ?? '',
    linkedAt: j['linkedAt'] ?? 0,
    isFake: j['isFake'] ?? false,
    isBanned: j['isBanned'] ?? false,
    isMod: j['isMod'] ?? false,
    activities: (j['activities'] as List?)?.map((a) => DeviceActivity.fromJson(a as Map<String, dynamic>)).toList() ?? [],
  );
}

class DeviceActivity {
  final String action;
  final int ts;
  final String detail;

  DeviceActivity({required this.action, required this.ts, this.detail = ''});

  Map<String, dynamic> toJson() => {'action': action, 'ts': ts, 'detail': detail};
  factory DeviceActivity.fromJson(Map<String, dynamic> j) => DeviceActivity(
    action: j['action'] ?? '',
    ts: j['ts'] ?? 0,
    detail: j['detail'] ?? '',
  );
}

class DeviceLinkRequest {
  final String requesterFipId;
  final String requesterName;
  final String code;
  final int ts;

  DeviceLinkRequest({required this.requesterFipId, required this.requesterName, required this.code, required this.ts});

  Map<String, dynamic> toJson() => {'requesterFipId': requesterFipId, 'requesterName': requesterName, 'code': code, 'ts': ts};
  factory DeviceLinkRequest.fromJson(Map<String, dynamic> j) => DeviceLinkRequest(
    requesterFipId: j['requesterFipId'] ?? '',
    requesterName: j['requesterName'] ?? '',
    code: j['code'] ?? '',
    ts: j['ts'] ?? 0,
  );
}

class DeviceManager {
  static const _kLinkedDevicesKey = 'knk_linked_devices_v1';
  static const _kBannedServersKey = 'knk_banned_servers_v1';
  static const _kPendingLinkCodeKey = 'knk_pending_link_code_v1';
  static const _kDeviceRoleKey = 'knk_device_role_v1';
  static const _kMainDeviceFipKey = 'knk_main_device_fip_v1';

  static String generateCode() => generateCodeWithLength(9);

  static String generateCodeWithLength(int length) {
    final rng = Random.secure();
    return List.generate(length, (_) => rng.nextInt(10)).join();
  }

  static Future<List<LinkedDevice>> loadLinkedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLinkedDevicesKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => LinkedDevice.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveLinkedDevices(List<LinkedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLinkedDevicesKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
  }

  static Future<void> addLinkedDevice(LinkedDevice device) async {
    final devices = await loadLinkedDevices();
    devices.add(device);
    await saveLinkedDevices(devices);
  }

  static Future<void> removeDevice(String deviceId) async {
    final devices = await loadLinkedDevices();
    devices.removeWhere((d) => d.deviceId == deviceId);
    await saveLinkedDevices(devices);
  }

  static Future<void> banDevice(String deviceId) async {
    final devices = await loadLinkedDevices();
    for (final d in devices) {
      if (d.deviceId == deviceId) {
        d.isBanned = true;
        break;
      }
    }
    await saveLinkedDevices(devices);
  }

  static Future<void> toggleMod(String deviceId) async {
    final devices = await loadLinkedDevices();
    for (final d in devices) {
      if (d.deviceId == deviceId) {
        d.isMod = !d.isMod;
        break;
      }
    }
    await saveLinkedDevices(devices);
  }

  static Future<List<String>> loadBannedServers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kBannedServersKey);
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  static Future<void> addBannedServer(String serverUrl, String fipId) async {
    final list = await loadBannedServers();
    final key = '$fipId@$serverUrl';
    if (!list.contains(key)) {
      list.add(key);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBannedServersKey, jsonEncode(list));
    }
  }

  static Future<bool> isServerBanned(String serverUrl, String fipId) async {
    final list = await loadBannedServers();
    return list.contains('$fipId@$serverUrl');
  }

  static Future<void> savePendingLinkCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingLinkCodeKey, code);
  }

  static Future<String?> loadPendingLinkCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPendingLinkCodeKey);
  }

  static Future<void> clearPendingLinkCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingLinkCodeKey);
  }

  // 'main', 'secondary', 'fake'
  static Future<String> loadDeviceRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDeviceRoleKey) ?? 'main';
  }

  static Future<void> saveDeviceRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceRoleKey, role);
  }

  static Future<String?> loadMainDeviceFip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMainDeviceFipKey);
  }

  static Future<void> saveMainDeviceFip(String fipId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMainDeviceFipKey, fipId);
  }

  static Future<void> logActivity(String deviceId, String action, {String detail = ''}) async {
    final devices = await loadLinkedDevices();
    for (final d in devices) {
      if (d.deviceId == deviceId) {
        d.activities.insert(0, DeviceActivity(action: action, ts: DateTime.now().millisecondsSinceEpoch, detail: detail));
        if (d.activities.length > 200) d.activities = d.activities.sublist(0, 200);
        break;
      }
    }
    await saveLinkedDevices(devices);
  }
}
