import 'dart:convert';
import 'package:http/http.dart' as http;
import 'e2e.dart';
import 'i18n.dart';

const String bridgeUrl = 'https://photon-chat.onrender.com';

class PhotonApi {
  static Uri _u(String serverUrl, String path) {
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return Uri.parse('$base$path');
  }

  // Render sunucusunu uyanık tutar (ücretsiz planda uyuma önleme)
  static Future<void> pingServer(String serverUrl) async {
    try {
      await http.get(_u(serverUrl, '/lookup/00000'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  // --- Bridge: global kod rehberi ---

  /// [actor] claims the code on the bridge so nobody else can repoint it.
  static Future<void> registerOnBridge(String code, String myServerUrl, {String? actor}) async {
    try {
      await http.post(_u(bridgeUrl, '/registry/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': code, 'serverUrl': myServerUrl, if (actor != null) 'actor': actor}));
    } catch (_) {}
  }

  static Future<String?> lookupServerOnBridge(String code) async {
    try {
      final r = await http.get(_u(bridgeUrl, '/registry/lookup/$code'));
      if (r.statusCode == 200) {
        return (jsonDecode(r.body) as Map<String, dynamic>)['serverUrl'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // --- Presence ---

  static Future<void> registerPresence(String myServerUrl, String fipId, String code, String name, {String statusMsg = '', String avatar = '', String bio = '', String? publicKey}) async {
    try {
      String? pk = publicKey;
      if (pk == null) {
        try { pk = await getMyPublicKeyBase64(); } catch (_) {}
      }
      await http.post(_u(myServerUrl, '/presence'), headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId, 'code': code, 'name': name, 'serverUrl': myServerUrl, 'statusMsg': statusMsg, 'avatar': avatar, 'bio': bio, if (pk != null) 'publicKey': pk}));
      await registerOnBridge(code, myServerUrl, actor: fipId);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getProfile(String serverUrl, String fipId) async {
    try {
      final r = await http.get(_u(serverUrl, '/profile/$fipId'));
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<void> markRead(String serverUrl, String chatKey, String fipId) async {
    try {
      await http.post(_u(serverUrl, '/chat/$chatKey/read'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId}));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getReadStatus(String serverUrl, String chatKey) async {
    try {
      final r = await http.get(_u(serverUrl, '/chat/$chatKey/read'));
      if (r.statusCode == 200) return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {}
    return {};
  }

  static Future<void> deleteMessage(String serverUrl, String chatKey, String msgId, {required String actor}) async {
    try {
      await http.delete(_u(serverUrl, '/chat/$chatKey/msg/$msgId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'actor': actor}));
    } catch (_) {}
  }

  static Future<void> editMessage(String serverUrl, String chatKey, String msgId, String newText, {required String actor}) async {
    try {
      await http.put(_u(serverUrl, '/chat/$chatKey/msg/$msgId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': newText, 'actor': actor}));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> lookupByCodeFromBridge(String code) async {
    final serverUrl = await lookupServerOnBridge(code);
    if (serverUrl == null) return null;
    final info = await lookupByCode(serverUrl, code);
    if (info == null) return null;
    return {...info, 'serverUrl': serverUrl};
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
    String bio = '',
    String? fromPublicKey,
  }) async {
    await http.post(_u(toServerUrl, '/requests/$toFipId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fromFipId': fromFipId, 'fromCode': fromCode, 'fromName': fromName, 'fromServerUrl': fromServerUrl, 'bio': bio, if (fromPublicKey != null) 'fromPublicKey': fromPublicKey}));
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

  /// Mesajı gönderir; (delivered, msgId) döner.
  static Future<(bool, String?)> sendMessage({required String receiverServerUrl, required String chatKey, required String from, required String text, required int ts, Map<String, dynamic>? replyTo, String? toFipId, String? senderName, String? imageData, bool nsfw = false}) async {
    try {
      final body = <String, dynamic>{'from': from, 'text': text, 'ts': ts};
      if (replyTo != null) body['replyTo'] = replyTo;
      if (toFipId != null) body['toFipId'] = toFipId;
      if (senderName != null) body['fromName'] = senderName;
      if (imageData != null) { body['type'] = 'image'; body['imageData'] = imageData; body['nsfw'] = nsfw; }
      final r = await http.post(_u(receiverServerUrl, '/chat/$chatKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body));
      if (r.statusCode == 200) {
        final respBody = jsonDecode(r.body) as Map<String, dynamic>;
        return (true, respBody['msgId'] as String?);
      }
    } catch (_) {}
    return (false, null);
  }

  // --- Notifications ---

  /// [actor] must be someone [fipId] has accepted, or the server returns 403.
  static Future<void> sendNotification(String serverUrl, String fipId, String title, String body, {required String actor}) async {
    try {
      await http.post(_u(serverUrl, '/notifs/$fipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'title': title, 'body': body, 'actor': actor}));
    } catch (_) {}
  }

  static Future<void> deleteNotif(String serverUrl, String fipId, int ts) async {
    try { await http.delete(_u(serverUrl, '/notifs/$fipId/$ts')); } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getNotifications(String serverUrl, String fipId) async {
    try {
      final r = await http.get(_u(serverUrl, '/notifs/$fipId'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> deleteChat(String serverUrl, String chatKey, {required String actor}) async {
    try {
      await http.delete(_u(serverUrl, '/chat/$chatKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'actor': actor}));
    } catch (_) {}
  }

  static Future<void> deactivate(String myServerUrl, String fipId) async {
    try {
      await http.post(_u(myServerUrl, '/deactivate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId}));
    } catch (_) {}
  }

  // --- Typing indicator ---

  static Future<void> sendTyping(String receiverServerUrl, String chatKey, String fipId) async {
    try {
      await http.post(_u(receiverServerUrl, '/typing/$chatKey'),
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

  // --- Group API ---

  static Future<(Map<String, dynamic>?, String?)> createGroup(String myServerUrl, {
    required String ownerFipId, required String ownerName, required String name, required String ownerServerUrl, String description = '',
  }) async {
    try {
      final r = await http.post(_u(myServerUrl, '/groups'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'ownerFipId': ownerFipId, 'ownerName': ownerName, 'name': name,
            'ownerServerUrl': ownerServerUrl, 'description': description,
            // Legacy/new server compat
            'actor': ownerFipId, 'fipId': ownerFipId, 'from': ownerFipId,
          })).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200 || r.statusCode == 201) {
        return (jsonDecode(r.body) as Map<String, dynamic>, null);
      }
      String reason = 'HTTP ${r.statusCode}';
      try {
        final body = jsonDecode(r.body);
        if (body is Map && body['error'] is String) reason = '${body['error']} (HTTP ${r.statusCode})';
      } catch (_) {}
      return (null, reason);
    } catch (e) {
      return (null, '${AppLang.instance.t('networkError')}: $e');
    }
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

  static Future<void> rejectGroupMember(String myServerUrl, String groupId, String fipId, {required String actor}) async {
    try {
      await http.delete(_u(myServerUrl, '/groups/$groupId/join-requests/$fipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'actor': actor}));
    } catch (_) {}
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

  static Future<void> leaveGroup(String ownerServerUrl, String groupId, String fipId, {required String actor}) async {
    try {
      await http.delete(_u(ownerServerUrl, '/groups/$groupId/members/$fipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'actor': actor}));
    } catch (_) {}
  }

  // --- Group mute ---

  static Future<void> muteGroupMember(String ownerServerUrl, String groupId, String fipId, {required String actor}) async {
    try {
      await http.post(_u(ownerServerUrl, '/groups/$groupId/muted'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId, 'actor': actor}));
    } catch (_) {}
  }

  static Future<void> unmuteGroupMember(String ownerServerUrl, String groupId, String fipId, {required String actor}) async {
    try {
      await http.delete(_u(ownerServerUrl, '/groups/$groupId/muted/$fipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'actor': actor}));
    } catch (_) {}
  }

  static Future<List<String>> getMutedMembers(String ownerServerUrl, String groupId) async {
    try {
      final r = await http.get(_u(ownerServerUrl, '/groups/$groupId/muted'));
      if (r.statusCode == 200) return List<String>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  // --- Group key (E2E for groups) ---

  static Future<void> sendGroupKey(String ownerServerUrl, String groupId, String memberFipId, String encryptedKey, {required String actor}) async {
    try {
      await http.post(_u(ownerServerUrl, '/groups/$groupId/key/$memberFipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'encryptedKey': encryptedKey, 'actor': actor}));
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

  // --- Reactions ---

  static Future<void> reactMessage(String serverUrl, String chatKey, String msgId, String fipId, String emoji) async {
    try {
      await http.post(_u(serverUrl, '/chat/$chatKey/msg/$msgId/react'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId, 'emoji': emoji}));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getChatReactions(String serverUrl, String chatKey) async {
    try {
      final r = await http.get(_u(serverUrl, '/chat/$chatKey/reactions'));
      if (r.statusCode == 200) return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {}
    return {};
  }

  // --- Group announcements ---

  static Future<void> sendGroupAnnouncement(String ownerServerUrl, String groupId, {
    required String from, required String fromName, required String text,
  }) async {
    try {
      await http.post(_u(ownerServerUrl, '/groups/$groupId/announce'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'from': from, 'fromName': fromName, 'text': text}));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getGroupAnnouncements(String myServerUrl, String groupId) async {
    try {
      final r = await http.get(_u(myServerUrl, '/groups/$groupId/announcements'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  // --- Group polls ---

  static Future<void> voteOnPoll(String ownerServerUrl, String groupId, String pollMsgId, String fipId, int optionIndex) async {
    try {
      await http.post(_u(ownerServerUrl, '/groups/$groupId/messages/$pollMsgId/vote'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fipId': fipId, 'optionIndex': optionIndex}));
    } catch (_) {}
  }

  static Future<void> sendGroupPoll(List<String> memberServerUrls, String groupId, {
    required String from, required String fromName, required String question, required List<String> options, required int ts,
  }) async {
    for (final url in memberServerUrls) {
      try {
        await http.post(_u(url, '/groups/$groupId/messages'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'from': from, 'fromName': fromName, 'type': 'poll', 'question': question, 'options': options, 'votes': {}, 'ts': ts}));
      } catch (_) {}
    }
  }

  // --- Device Linking ---

  static Future<void> sendDeviceLinkRequest(String serverUrl, String ownerFipId, {
    required String requesterFipId, required String requesterName,
  }) async {
    try {
      await http.post(_u(serverUrl, '/device-link/$ownerFipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requesterFipId': requesterFipId, 'requesterName': requesterName, 'ts': DateTime.now().millisecondsSinceEpoch}));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getDeviceLinkRequests(String serverUrl, String fipId) async {
    try {
      final r = await http.get(_u(serverUrl, '/device-link/$fipId'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> respondDeviceLink(String serverUrl, String ownerFipId, {
    required String requesterFipId, required String status, String code = '',
  }) async {
    try {
      await http.post(_u(serverUrl, '/device-link/$ownerFipId/respond'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requesterFipId': requesterFipId, 'status': status, 'code': code, 'actor': ownerFipId}));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getDeviceLinkStatus(String serverUrl, String requesterFipId) async {
    try {
      final r = await http.get(_u(serverUrl, '/device-link-status/$requesterFipId'));
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<void> submitDeviceLinkCode(String serverUrl, String ownerFipId, {
    required String requesterFipId, required String code,
  }) async {
    try {
      await http.post(_u(serverUrl, '/device-link/$ownerFipId/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requesterFipId': requesterFipId, 'code': code}));
    } catch (_) {}
  }

  static Future<void> logDeviceActivity(String serverUrl, String ownerFipId, {
    required String deviceId, required String action, String detail = '', required String actor,
  }) async {
    try {
      await http.post(_u(serverUrl, '/device-activity/$ownerFipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'deviceId': deviceId, 'action': action, 'detail': detail, 'ts': DateTime.now().millisecondsSinceEpoch, 'actor': actor}));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getDeviceActivities(String serverUrl, String ownerFipId, String deviceId) async {
    try {
      final r = await http.get(_u(serverUrl, '/device-activity/$ownerFipId/$deviceId'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> kickDevice(String serverUrl, String ownerFipId, String deviceId) async {
    try {
      await http.delete(_u(serverUrl, '/device-link/$ownerFipId/$deviceId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'actor': ownerFipId}));
    } catch (_) {}
  }

  static Future<void> banDeviceOnServer(String serverUrl, String ownerFipId, String bannedFipId) async {
    try {
      await http.post(_u(serverUrl, '/device-ban/$ownerFipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'bannedFipId': bannedFipId, 'actor': ownerFipId}));
    } catch (_) {}
  }

  static Future<List<String>> getBannedDevices(String serverUrl, String ownerFipId) async {
    try {
      final r = await http.get(_u(serverUrl, '/device-ban/$ownerFipId'));
      if (r.statusCode == 200) return List<String>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  // --- Pulse AI ---

  /// [messages] format: [{'role':'user','content':'...'}, {'role':'assistant','content':'...'}, ...]
  // --- File sharing ---

  static Future<(bool, String?)> sendFileMessage({required String receiverServerUrl, required String chatKey, required String from, required String fileName, required String fileData, required int fileSize, required int ts, String? toFipId, String? senderName}) async {
    try {
      final body = <String, dynamic>{'from': from, 'text': '[Dosya: $fileName]', 'ts': ts, 'type': 'file', 'fileName': fileName, 'fileData': fileData, 'fileSize': fileSize};
      if (toFipId != null) body['toFipId'] = toFipId;
      if (senderName != null) body['fromName'] = senderName;
      final r = await http.post(_u(receiverServerUrl, '/chat/$chatKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body));
      if (r.statusCode == 200) {
        final respBody = jsonDecode(r.body) as Map<String, dynamic>;
        return (true, respBody['msgId'] as String?);
      }
    } catch (_) {}
    return (false, null);
  }

  // --- Stories ---

  static Future<void> postStory(String serverUrl, String fipId, Map<String, dynamic> storyData) async {
    try {
      await http.post(_u(serverUrl, '/stories/$fipId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({...storyData, 'actor': fipId}));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getStories(String serverUrl, String fipId) async {
    try {
      final r = await http.get(_u(serverUrl, '/stories/$fipId'));
      if (r.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  static Future<void> deleteStory(String serverUrl, String fipId, String storyId) async {
    try {
      await http.delete(_u(serverUrl, '/stories/$fipId/$storyId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'actor': fipId}));
    } catch (_) {}
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
        return body['reply'] as String? ?? AppLang.instance.t('aiNoReply');
      }
      final err = jsonDecode(r.body)['error'] as String? ?? AppLang.instance.t('aiGenericError');
      return err;
    } catch (_) {
      return AppLang.instance.t('aiUnreachable');
    }
  }

}