import 'dart:convert';
import 'package:http/http.dart' as http;

/// Bir kişinin sunucudaki durumu.
enum ContactStatus {
  /// Sunucuda kayıtlı (uygulamayı açmış).
  active,

  /// Hesabını sildi. Kişi listeden kaldırılabilir.
  deactivated,

  /// Sunucu onu tanımıyor (ör. sunucu yeniden başladı) veya sunucuya ulaşılamadı.
  /// Kişi asla bu duruma göre silinmez.
  unknown,
}

/// Grup mesajı gönderme sonucu: null = başarılı, aksi halde kullanıcıya gösterilecek hata.
typedef SendResult = String?;

class KnkApi {
  static const String bridgeUrl = 'https://photon-chat.onrender.com';

  static const _json = {'Content-Type': 'application/json'};
  static const _timeout = Duration(seconds: 15);

  /// Tek bir istemci: bağlantılar (keep-alive) yeniden kullanılır, her istekte yeni TLS el sıkışması yapılmaz.
  static http.Client _client = http.Client();

  /// Testlerde sahte istemci enjekte etmek için.
  static set client(http.Client c) => _client = c;

  static Uri _u(String serverUrl, String path) {
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return Uri.parse('$base$path');
  }

  static String _seg(String s) => Uri.encodeComponent(s);

  static Map<String, String>? _auth(String? token) => token == null ? null : {'x-group-token': token};

  static Future<http.Response> _get(String serverUrl, String path, {Duration timeout = _timeout, String? token}) =>
      _client.get(_u(serverUrl, path), headers: _auth(token)).timeout(timeout);

  static Future<http.Response> _post(String serverUrl, String path, Object body, {Duration timeout = _timeout, String? token}) =>
      _client.post(_u(serverUrl, path), headers: {..._json, ...?_auth(token)}, body: jsonEncode(body)).timeout(timeout);

  static Future<http.Response> _delete(String serverUrl, String path, {String? token}) =>
      _client.delete(_u(serverUrl, path), headers: _auth(token)).timeout(_timeout);

  static List<Map<String, dynamic>> _list(String body) =>
      (jsonDecode(body) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  /// Adresin bir Photon Chat sunucusu olup olmadığını kontrol eder.
  /// Ücretsiz sunucular uykudan uyanırken uzun sürebilir; zaman aşımında [TimeoutException] fırlatır.
  static Future<bool> isPhotonServer(String url) async {
    final h = await _get(url, '/health', timeout: const Duration(seconds: 60));
    if (h.statusCode == 200) {
      try {
        if ((jsonDecode(h.body) as Map<String, dynamic>)['app'] == 'photon-chat') return true;
      } catch (_) {}
    }
    // Eski sunucular için geri uyumluluk: /lookup uç noktası 404 veya JSON döner.
    final r = await _get(url, '/lookup/00000', timeout: const Duration(seconds: 30));
    return r.statusCode == 404 || (r.statusCode == 200 && r.body.trim().startsWith('{'));
  }

  // --- Bridge: global kod rehberi ---

  static Future<void> registerOnBridge(String code, String myServerUrl) async {
    try {
      await _post(bridgeUrl, '/registry/register', {'code': code, 'serverUrl': myServerUrl});
    } catch (_) {}
  }

  static Future<void> unregisterOnBridge(String code, String myServerUrl) async {
    try {
      await _post(bridgeUrl, '/registry/unregister', {'code': code, 'serverUrl': myServerUrl});
    } catch (_) {}
  }

  static Future<String?> lookupServerOnBridge(String code) async {
    try {
      // Render ücretsiz planda sunucu uykudan uyanırken ilk istek uzun sürebilir.
      final r = await _get(bridgeUrl, '/registry/lookup/${_seg(code)}', timeout: const Duration(seconds: 60));
      if (r.statusCode == 200) {
        return (jsonDecode(r.body) as Map<String, dynamic>)['serverUrl'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // --- Presence ---

  static Future<bool> registerPresence(String myServerUrl, String fipId, String code, String name, {String? publicKey}) async {
    var ok = false;
    try {
      final r = await _post(myServerUrl, '/presence', {
        'fipId': fipId, 'code': code, 'name': name, 'serverUrl': myServerUrl,
        if (publicKey != null) 'publicKey': publicKey,
      });
      ok = r.statusCode == 200;
    } catch (_) {}
    await registerOnBridge(code, myServerUrl);
    return ok;
  }

  static Future<Map<String, dynamic>?> lookupByCode(String serverUrl, String code) async {
    try {
      final r = await _get(serverUrl, '/lookup/${_seg(code)}', timeout: const Duration(seconds: 60));
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// true dönerse istek karşı sunucuya ulaştı.
  static Future<bool> sendFriendRequest({
    required String toServerUrl, required String toFipId,
    required String fromFipId, required String fromCode, required String fromName, required String fromServerUrl,
    String? fromPublicKey,
  }) async {
    try {
      final r = await _post(toServerUrl, '/requests/${_seg(toFipId)}', {
        'fromFipId': fromFipId, 'fromCode': fromCode, 'fromName': fromName, 'fromServerUrl': fromServerUrl,
        if (fromPublicKey != null) 'fromPublicKey': fromPublicKey,
      });
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Sunucuya ulaşılamazsa null döner (boş liste ile karıştırılmaması için).
  static Future<List<Map<String, dynamic>>?> getIncomingRequests(String myServerUrl, String myFipId) async {
    try {
      final r = await _get(myServerUrl, '/requests/${_seg(myFipId)}');
      if (r.statusCode == 200) return _list(r.body);
    } catch (_) {}
    return null;
  }

  /// İsteği kabul eder: kendi sunucumuzdaki isteği temizler ve isteği gönderenin
  /// sunucusuna "kabul edildi" bilgisini yazar (gönderen kendi sunucusunu dinler).
  static Future<void> acceptFriendRequest({
    required String myServerUrl, required String myFipId, required String otherFipId, String? otherServerUrl,
  }) async {
    final calls = <Future<void>>[
      _post(myServerUrl, '/accept', {'myFipId': myFipId, 'otherFipId': otherFipId}).then((_) {}, onError: (_) {}),
    ];
    if (otherServerUrl != null && otherServerUrl.isNotEmpty) {
      calls.add(_post(otherServerUrl, '/accept', {'myFipId': otherFipId, 'otherFipId': myFipId}).then((_) {}, onError: (_) {}));
    }
    await Future.wait(calls);
  }

  static Future<void> declineFriendRequest({required String myServerUrl, required String myFipId, required String otherFipId}) async {
    try { await _delete(myServerUrl, '/requests/${_seg(myFipId)}/${_seg(otherFipId)}'); } catch (_) {}
  }

  static Future<List<String>> getAcceptedRequests(String myServerUrl, String myFipId) async {
    try {
      final r = await _get(myServerUrl, '/accepted/${_seg(myFipId)}');
      if (r.statusCode == 200) return List<String>.from(jsonDecode(r.body) as List);
    } catch (_) {}
    return [];
  }

  /// Bir sunucudaki birden çok kişinin durumunu tek istekte sorgular.
  static Future<Map<String, ContactStatus>> getStatuses(String serverUrl, List<String> fipIds) async {
    final result = {for (final id in fipIds) id: ContactStatus.unknown};
    if (fipIds.isEmpty || serverUrl.isEmpty) return result;
    try {
      final r = await _post(serverUrl, '/status', {'fipIds': fipIds});
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        for (final id in List<String>.from(body['active'] as List? ?? const [])) {
          result[id] = ContactStatus.active;
        }
        for (final id in List<String>.from(body['deactivated'] as List? ?? const [])) {
          result[id] = ContactStatus.deactivated;
        }
      }
    } catch (_) {}
    return result;
  }

  static Future<ContactStatus> getStatus(String serverUrl, String fipId) async =>
      (await getStatuses(serverUrl, [fipId]))[fipId] ?? ContactStatus.unknown;

  /// Sunucuya ulaşılamazsa null döner.
  static Future<List<Map<String, dynamic>>?> getMessages(String chatKey, {required String receiverServerUrl}) async {
    try {
      final r = await _get(receiverServerUrl, '/chat/${_seg(chatKey)}');
      if (r.statusCode == 200) return _list(r.body);
    } catch (_) {}
    return null;
  }

  /// Mesajı verilen sunucuya yazar; true dönerse sunucu kaydetti.
  static Future<bool> sendMessage({required String receiverServerUrl, required String chatKey, required String from, required String text, required int ts}) async {
    try {
      final r = await _post(receiverServerUrl, '/chat/${_seg(chatKey)}', {'from': from, 'text': text, 'ts': ts});
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  static Future<void> deleteChat(String serverUrl, String chatKey) async {
    try { await _delete(serverUrl, '/chat/${_seg(chatKey)}'); } catch (_) {}
  }

  static Future<void> deactivate(String myServerUrl, String fipId) async {
    try { await _post(myServerUrl, '/deactivate', {'fipId': fipId}); } catch (_) {}
  }

  // --- Typing indicator ---

  /// "Yazıyor" bilgisini karşı tarafın sunucusuna yazar (karşı taraf kendi sunucusunu dinler).
  /// [stop] true ise gösterge hemen kapatılır (mesaj gönderildiğinde).
  static Future<void> sendTyping(String contactServerUrl, String chatKey, String fipId, {bool stop = false}) async {
    try { await _post(contactServerUrl, '/typing/${_seg(chatKey)}', {'fipId': fipId, if (stop) 'stop': true}); } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getTyping(String serverUrl, String chatKey) async {
    try {
      final r = await _get(serverUrl, '/typing/${_seg(chatKey)}');
      if (r.statusCode == 200) return _list(r.body);
    } catch (_) {}
    return [];
  }

  // --- Group API ---
  // Bir grubun tüm verisi (üyeler, mesajlar, susturma) grup sahibinin sunucusunda tutulur.
  // [token]: grubu oluştururken (sahip) veya katılma isteği gönderirken (üye) alınan gizli anahtar.

  /// Başarılıysa {groupId, groupCode, name, ownerFipId, ownerServerUrl, token} döner.
  static Future<Map<String, dynamic>?> createGroup(String myServerUrl, {
    required String ownerFipId, required String ownerName, required String name, required String ownerServerUrl,
  }) async {
    try {
      final r = await _post(myServerUrl, '/groups', {'ownerFipId': ownerFipId, 'ownerName': ownerName, 'name': name, 'ownerServerUrl': ownerServerUrl});
      if (r.statusCode == 200 || r.statusCode == 201) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getGroupByCode(String ownerServerUrl, String code) async {
    try {
      final r = await _get(ownerServerUrl, '/groups/by-code/${_seg(code)}', timeout: const Duration(seconds: 60));
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  /// Katılma isteği gönderir. Başarılıysa (üye token'ı, null), aksi halde (null, hata) döner.
  static Future<(String?, String?)> sendGroupJoinRequest(String ownerServerUrl, String groupId, {
    required String fromFipId, required String fromName, required String fromServerUrl,
  }) async {
    try {
      final r = await _post(ownerServerUrl, '/groups/${_seg(groupId)}/join-requests',
          {'fromFipId': fromFipId, 'fromName': fromName, 'fromServerUrl': fromServerUrl});
      Map<String, dynamic>? body;
      try { body = jsonDecode(r.body) as Map<String, dynamic>; } catch (_) {}
      final token = body?['token'] as String?;
      if (r.statusCode == 200 && token != null) return (token, null);
      if (r.statusCode == 200) return (null, 'Grup sunucusu eski bir sürüm. Grup sahibinden sunucusunu güncellemesini iste.');
      return (null, (body?['error'] as String?) ?? 'Katılma isteği gönderilemedi (${r.statusCode}).');
    } catch (_) {}
    return (null, 'Grup sunucusuna ulaşılamadı. Tekrar dene.');
  }

  /// Sunucuya ulaşılamazsa null döner.
  static Future<List<Map<String, dynamic>>?> getGroupJoinRequests(String ownerServerUrl, String groupId) async {
    try {
      final r = await _get(ownerServerUrl, '/groups/${_seg(groupId)}/join-requests');
      if (r.statusCode == 200) return _list(r.body);
    } catch (_) {}
    return null;
  }

  static Future<bool> acceptGroupMember(String ownerServerUrl, String groupId, String token, {required String fipId}) async {
    try {
      final r = await _post(ownerServerUrl, '/groups/${_seg(groupId)}/members', {'fipId': fipId}, token: token);
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  static Future<bool> rejectGroupMember(String ownerServerUrl, String groupId, String token, String fipId) async {
    try {
      final r = await _delete(ownerServerUrl, '/groups/${_seg(groupId)}/join-requests/${_seg(fipId)}', token: token);
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Grup bilgisi: {members, muted, ownerFipId, name}.
  /// Grup yoksa {'notFound': true}, sunucuya ulaşılamazsa null döner.
  static Future<Map<String, dynamic>?> getGroupMembers(String ownerServerUrl, String groupId) async {
    try {
      final r = await _get(ownerServerUrl, '/groups/${_seg(groupId)}/members');
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 404) return {'notFound': true};
    } catch (_) {}
    return null;
  }

  static Future<SendResult> sendGroupMessage(String ownerServerUrl, String groupId, String token, {
    required String fromName, required String text, required int ts,
  }) async {
    try {
      final r = await _post(ownerServerUrl, '/groups/${_seg(groupId)}/messages',
          {'fromName': fromName, 'text': text, 'ts': ts}, token: token);
      if (r.statusCode == 200) return null;
      if (r.statusCode == 404) return 'Grup artık mevcut değil.';
      try {
        final err = (jsonDecode(r.body) as Map<String, dynamic>)['error'] as String?;
        if (err != null) return err;
      } catch (_) {}
      return 'Mesaj gönderilemedi (${r.statusCode}).';
    } catch (_) {
      return 'Grup sunucusuna ulaşılamadı. Bağlantını kontrol et.';
    }
  }

  /// Yalnızca grup üyeleri okuyabilir. Üye değilsek (403) veya grup yoksa (404) boş liste,
  /// sunucuya ulaşılamazsa null döner.
  static Future<List<Map<String, dynamic>>?> getGroupMessages(String ownerServerUrl, String groupId, String token) async {
    try {
      final r = await _get(ownerServerUrl, '/groups/${_seg(groupId)}/messages', token: token);
      if (r.statusCode == 200) return _list(r.body);
      if (r.statusCode == 403 || r.statusCode == 404) return [];
    } catch (_) {}
    return null;
  }

  /// Üyeyi gruptan çıkarır (sahip token'ı ile) veya kendi token'ımızla gruptan ayrılır.
  static Future<bool> leaveGroup(String ownerServerUrl, String groupId, String token, String fipId) async {
    try {
      final r = await _delete(ownerServerUrl, '/groups/${_seg(groupId)}/members/${_seg(fipId)}', token: token);
      return r.statusCode == 200 || r.statusCode == 404;
    } catch (_) {}
    return false;
  }

  static Future<bool> deleteGroup(String ownerServerUrl, String groupId, String token) async {
    try {
      final r = await _delete(ownerServerUrl, '/groups/${_seg(groupId)}', token: token);
      return r.statusCode == 200 || r.statusCode == 404;
    } catch (_) {}
    return false;
  }

  // --- Group mute (sahip token'ı gerekir) ---

  static Future<bool> muteGroupMember(String ownerServerUrl, String groupId, String token, String fipId) async {
    try {
      final r = await _post(ownerServerUrl, '/groups/${_seg(groupId)}/muted', {'fipId': fipId}, token: token);
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  static Future<bool> unmuteGroupMember(String ownerServerUrl, String groupId, String token, String fipId) async {
    try {
      final r = await _delete(ownerServerUrl, '/groups/${_seg(groupId)}/muted/${_seg(fipId)}', token: token);
      return r.statusCode == 200;
    } catch (_) {}
    return false;
  }

  // --- Pulse AI ---

  /// [messages] format: [{'role':'user','content':'...'}, {'role':'assistant','content':'...'}, ...]
  /// Başarılıysa (reply, null), hata varsa (null, hata mesajı) döner.
  static Future<(String?, String?)> chatWithPulseAI(String myServerUrl, List<Map<String, String>> messages) async {
    try {
      final r = await _post(myServerUrl, '/ai/chat', {'messages': messages}, timeout: const Duration(seconds: 45));
      Map<String, dynamic>? body;
      try { body = jsonDecode(r.body) as Map<String, dynamic>; } catch (_) {}
      if (r.statusCode == 200) {
        final reply = body?['reply'] as String?;
        if (reply != null && reply.trim().isNotEmpty) return (reply, null);
        return (null, 'Yanıt alınamadı.');
      }
      if (r.statusCode == 404) return (null, 'Sunucun Pulse AI desteklemiyor. Sunucunu güncelle.');
      return (null, (body?['error'] as String?) ?? 'Bir hata oluştu (${r.statusCode}).');
    } catch (_) {
      return (null, "Pulse AI'e ulaşılamadı. Sunucu bağlantını kontrol et.");
    }
  }
}
