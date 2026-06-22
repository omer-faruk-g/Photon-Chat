import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'photon_api.dart';

class QueuedMessage {
  final String chatKey;
  final String receiverServerUrl;
  final String from;
  final String text;
  final int ts;
  final String? replyToMsgId;
  final String? replyToFrom;
  final String? replyToText;
  final String? toFipId;
  final String? senderName;
  final bool isGroup;
  final List<String>? groupMemberUrls;
  final String? groupId;
  final String? fromName;
  bool sending;

  QueuedMessage({
    required this.chatKey,
    required this.receiverServerUrl,
    required this.from,
    required this.text,
    required this.ts,
    this.replyToMsgId,
    this.replyToFrom,
    this.replyToText,
    this.toFipId,
    this.senderName,
    this.isGroup = false,
    this.groupMemberUrls,
    this.groupId,
    this.fromName,
    this.sending = false,
  });

  Map<String, dynamic> toJson() => {
        'chatKey': chatKey,
        'receiverServerUrl': receiverServerUrl,
        'from': from,
        'text': text,
        'ts': ts,
        if (replyToMsgId != null) 'replyToMsgId': replyToMsgId,
        if (replyToFrom != null) 'replyToFrom': replyToFrom,
        if (replyToText != null) 'replyToText': replyToText,
        if (toFipId != null) 'toFipId': toFipId,
        if (senderName != null) 'senderName': senderName,
        'isGroup': isGroup,
        if (groupMemberUrls != null) 'groupMemberUrls': groupMemberUrls,
        if (groupId != null) 'groupId': groupId,
        if (fromName != null) 'fromName': fromName,
      };

  factory QueuedMessage.fromJson(Map<String, dynamic> j) => QueuedMessage(
        chatKey: j['chatKey'] as String,
        receiverServerUrl: j['receiverServerUrl'] as String,
        from: j['from'] as String,
        text: j['text'] as String,
        ts: j['ts'] as int,
        replyToMsgId: j['replyToMsgId'] as String?,
        replyToFrom: j['replyToFrom'] as String?,
        replyToText: j['replyToText'] as String?,
        toFipId: j['toFipId'] as String?,
        senderName: j['senderName'] as String?,
        isGroup: j['isGroup'] as bool? ?? false,
        groupMemberUrls: (j['groupMemberUrls'] as List?)?.cast<String>(),
        groupId: j['groupId'] as String?,
        fromName: j['fromName'] as String?,
      );
}

class OfflineQueue {
  static final OfflineQueue instance = OfflineQueue._();
  OfflineQueue._();

  static const _storageKey = 'knk_offline_queue_v1';

  final List<QueuedMessage> _queue = [];
  List<QueuedMessage> get queue => List.unmodifiable(_queue);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      _queue.clear();
      for (final item in list) {
        _queue.add(QueuedMessage.fromJson(Map<String, dynamic>.from(item as Map)));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_queue.map((m) => m.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  Future<void> enqueue(QueuedMessage msg) async {
    _queue.add(msg);
    await _save();
  }

  Future<void> flush() async {
    if (_queue.isEmpty) return;
    final toRemove = <QueuedMessage>[];
    for (final msg in _queue) {
      if (msg.sending) continue;
      msg.sending = true;
      try {
        if (msg.isGroup) {
          await _sendGroupMessage(msg);
        } else {
          await _sendDirectMessage(msg);
        }
        toRemove.add(msg);
      } on SocketException {
        msg.sending = false;
        break; // network still down, stop trying
      } on TimeoutException {
        msg.sending = false;
        break;
      } catch (_) {
        msg.sending = false;
      }
    }
    if (toRemove.isNotEmpty) {
      _queue.removeWhere((m) => toRemove.contains(m));
      await _save();
    }
  }

  Future<void> _sendDirectMessage(QueuedMessage msg) async {
    final replyData = msg.replyToMsgId != null
        ? {'msgId': msg.replyToMsgId, 'from': msg.replyToFrom, 'text': msg.replyToText}
        : null;

    // Send to own server
    final (ok1, _) = await PhotonApi.sendMessage(
      receiverServerUrl: msg.receiverServerUrl,
      chatKey: msg.chatKey,
      from: msg.from,
      text: msg.text,
      ts: msg.ts,
      replyTo: replyData,
    );
    if (!ok1) throw const SocketException('Failed to reach server');

    // Send to contact server (if toFipId is set, this is the contact copy)
    if (msg.toFipId != null) {
      await PhotonApi.sendMessage(
        receiverServerUrl: msg.receiverServerUrl,
        chatKey: msg.chatKey,
        from: msg.from,
        text: msg.text,
        ts: msg.ts,
        replyTo: replyData,
        toFipId: msg.toFipId,
        senderName: msg.senderName,
      );
    }
  }

  Future<void> _sendGroupMessage(QueuedMessage msg) async {
    if (msg.groupMemberUrls == null || msg.groupId == null) return;
    await PhotonApi.sendGroupMessage(
      msg.groupMemberUrls!,
      msg.groupId!,
      from: msg.from,
      fromName: msg.fromName ?? '',
      text: msg.text,
      ts: msg.ts,
    );
  }

  List<QueuedMessage> getForChat(String chatKey) {
    return _queue.where((m) => m.chatKey == chatKey).toList();
  }
}
