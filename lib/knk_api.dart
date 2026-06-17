import 'dart:convert';
import 'package:http/http.dart' as http;

String chatKeyFor(String a, String b) {
  final sorted = [a, b]..sort();
  return '${sorted[0]}_${sorted[1]}';
}

class KnkApi {
  static Uri _u(String serverUrl, String path) {
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return Uri.parse('$base$path');
  }

  static Future<void> registerPresence(String myServerUrl, String fipId, String code, String name) async {
    try {
      await http.post(_u(myServerUrl, '/presence'), headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId, 'code': code, 'name': name}));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> lookupByCode(String serverUrl, String code) async {
    try {
      final r = await http.get(_u(serverUrl, '/lookup/$code'));
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<void> sendFriendRequest({
    required String toServerUrl, required String toFipId,
    required String fromFipId, required String fromCode, required String fromName, required String fromServerUrl,
    String? fromPublicKey,
  }) async {
    await http.post(_u(toServerUrl, '/requests/$toFipId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fromFipId': fromFipId, 'fromCode': fromCode, 'fromName': fromName, 'fromServerUrl': fromServerUrl, if (fromPublicKey != null) 'fromPublicKey': fromPublicKey}));
  }

  static Future<List<Map<String, dynamic>>> getIncomingRequests(String myServerUrl, String myFipId) async {
    try {
      final r = await http.get(_u(myServerUrl, '/requests/$myFipId'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> acceptFriendRequest({required String myServerUrl, required String myFipId, required String otherFipId}) async {
    try {
      await http.post(_u(myServerUrl, '/accept'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'myFipId': myFipId, 'otherFipId': otherFipId}));
    } catch (_) {}
  }

  static Future<List<String>> getAcceptedRequests(String myServerUrl, String myFipId) async {
    try {
      final r = await http.get(_u(myServerUrl, '/accepted/$myFipId'));
      if (r.statusCode == 200) return List<String>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<bool> isActive(String serverUrl, String fipId) async {
    try {
      final r = await http.post(_u(serverUrl, '/active'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipIds': [fipId]}));
      if (r.statusCode == 200) return (jsonDecode(r.body) as List).contains(fipId);
    } catch (_) {}
    return false;
  }

  static Future<List<Map<String, dynamic>>> getMessages(String chatKey, {required String receiverServerUrl}) async {
    try {
      final r = await http.get(_u(receiverServerUrl, '/chat/$chatKey'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<bool> sendMessage({required String receiverServerUrl, required String chatKey, required String from, required String text, required int ts}) async {
    try {
      final r = await http.post(_u(receiverServerUrl, '/chat/$chatKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'from': from, 'text': text, 'ts': ts}));
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  static Future<void> deleteChat(String serverUrl, String chatKey) async {
    try { await http.delete(_u(serverUrl, '/chat/$chatKey')); } catch (_) {}
  }

  static Future<void> deactivate(String myServerUrl, String fipId) async {
    try {
      await http.post(_u(myServerUrl, '/deactivate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId}));
    } catch (_) {}
  }

  static Future<void> sendTyping(String myServerUrl, String chatKey, String fipId) async {
    try {
      await http.post(_u(myServerUrl, '/typing/$chatKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId, 'ts': DateTime.now().millisecondsSinceEpoch}));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getTyping(String serverUrl, String chatKey) async {
    try {
      final r = await http.get(_u(serverUrl, '/typing/$chatKey'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> createGroup(String myServerUrl, {
    required String ownerFipId, required String ownerName, required String name, required String ownerServerUrl,
  }) async {
    try {
      final r = await http.post(_u(myServerUrl, '/groups'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ownerFipId': ownerFipId, 'ownerName': ownerName, 'name': name, 'ownerServerUrl': ownerServerUrl}));
      if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getGroupByCode(String ownerServerUrl, String code) async {
    try {
      final r = await http.get(_u(ownerServerUrl, '/groups/by-code/$code'));
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<void> sendGroupJoinRequest(String ownerServerUrl, String groupId, {
    required String fromFipId, required String fromName, required String fromServerUrl,
  }) async {
    try {
      await http.post(_u(ownerServerUrl, '/groups/$groupId/join-requests'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fromFipId': fromFipId, 'fromName': fromName, 'fromServerUrl': fromServerUrl}));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getGroupJoinRequests(String myServerUrl, String groupId) async {
    try {
      final r = await http.get(_u(myServerUrl, '/groups/$groupId/join-requests'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> acceptGroupMember(String myServerUrl, String groupId, {
    required String fipId, required String name, required String serverUrl,
  }) async {
    try {
      await http.post(_u(myServerUrl, '/groups/$groupId/members'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId, 'name': name, 'serverUrl': serverUrl}));
    } catch (_) {}
  }

  static Future<void> rejectGroupMember(String myServerUrl, String groupId, String fipId) async {
    try { await http.delete(_u(myServerUrl, '/groups/$groupId/join-requests/$fipId')); } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getGroupMembers(String ownerServerUrl, String groupId) async {
    try {
      final r = await http.get(_u(ownerServerUrl, '/groups/$groupId/members'));
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<void> sendGroupMessage(List<String> memberServerUrls, String groupId, {
    required String from, required String fromName, required String text, required int ts,
  }) async {
    for (final url in memberServerUrls) {
      try {
        await http.post(_u(url, '/groups/$groupId/messages'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'from': from, 'fromName': fromName, 'text': text, 'ts': ts}));
      } catch (_) {}
    }
  }

  static Future<List<Map<String, dynamic>>> getGroupMessages(String myServerUrl, String groupId) async {
    try {
      final r = await http.get(_u(myServerUrl, '/groups/$groupId/messages'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> leaveGroup(String ownerServerUrl, String groupId, String fipId) async {
    try { await http.delete(_u(ownerServerUrl, '/groups/$groupId/members/$fipId')); } catch (_) {}
  }

  static Future<void> muteGroupMember(String ownerServerUrl, String groupId, String fipId) async {
    try {
      await http.post(_u(ownerServerUrl, '/groups/$groupId/muted'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId}));
    } catch (_) {}
  }

  static Future<void> unmuteGroupMember(String ownerServerUrl, String groupId, String fipId) async {
    try { await http.delete(_u(ownerServerUrl, '/groups/$groupId/muted/$fipId')); } catch (_) {}
  }

  static Future<List<String>> getMutedMembers(String ownerServerUrl, String groupId) async {
    try {
      final r = await http.get(_u(ownerServerUrl, '/groups/$groupId/muted'));
      if (r.statusCode == 200) return List<String>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> sendGroupKey(String ownerServerUrl, String groupId, String memberFipId, String encryptedKey) async {
    try {
      await http.post(_u(ownerServerUrl, '/groups/$groupId/key/$memberFipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'encryptedKey': encryptedKey}));
    } catch (_) {}
  }

  static Future<String?> getGroupKey(String ownerServerUrl, String groupId, String myFipId) async {
    try {
      final r = await http.get(_u(ownerServerUrl, '/groups/$groupId/key/$myFipId'));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['encryptedKey'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<String> chatWithPulseAI(String myServerUrl, List<Map<String, String>> messages) async {
    try {
      final r = await http.post(
        _u(myServerUrl, '/ai/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'messages': messages}),
      ).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['reply'] as String? ?? 'Yanıt alınamadı.';
      }
      final err = jsonDecode(r.body)['error'] as String? ?? 'Bir hata oluştu.';
      return err;
    } catch (_) {
      return 'Pulse AI\'e ulaşılamadı. Sunucu bağlantını kontrol et.';
    }
  }
}
