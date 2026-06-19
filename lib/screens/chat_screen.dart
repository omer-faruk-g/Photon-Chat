import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../e2e.dart';
import '../theme.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';
import '../chat_wallpaper.dart';
import '../offline_queue.dart';
import '../translate_service.dart';
import 'package:cryptography/cryptography.dart';

class ChatScreen extends StatefulWidget {
  final FipBlock identity;
  final Contact contact;
  final String myServerUrl;

  const ChatScreen({super.key, required this.identity, required this.contact, required this.myServerUrl});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _draftCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<_DisplayMessage> _messages = [];
  late final String _chatKey;
  String _myDisplayName = '';
  bool _alive = true;
  bool _contactActive = true;
  String? _inputError;
  bool _contactTyping = false;
  bool _isBlocked = false;
  SecretKey? _sharedKey;
  String? _editingMsgId;
  Map<String, dynamic> _readStatus = {};
  Map<String, dynamic>? _replyToMsg;
  int _prevMsgCount = 0;
  final Map<String, String> _translations = {};
  final Map<String, String> _filtered = {};
  final Set<String> _translating = {};

  Timer? _typingDebounce;
  Timer? _typingPollTimer;

  @override
  void initState() {
    super.initState();
    _chatKey = chatKeyFor(widget.identity.fipId, widget.contact.fipId);
    LocalStore.loadDisplayName().then((n) { if (mounted) setState(() => _myDisplayName = n ?? ''); });
    _initE2E();
    _checkBlocked();
    _poll();
    _pollContactStatus();
    _startTypingPoll();
    _startReadPoll();
    _markRead();
  }

  Future<void> _initE2E() async {
    try {
      final info = await KnkApi.lookupByCode(widget.contact.serverUrl, widget.contact.code);
      final pubKey = info?['publicKey'] as String?;
      if (pubKey != null && pubKey.isNotEmpty) {
        final key = await deriveSharedKey(pubKey);
        if (mounted) setState(() => _sharedKey = key);
      }
    } catch (_) {}
  }

  Future<void> _checkBlocked() async {
    final blocked = await LocalStore.loadBlockList();
    if (mounted) setState(() => _isBlocked = blocked.contains(widget.contact.fipId));
  }

  Future<void> _markRead() async {
    await KnkApi.markRead(widget.myServerUrl, _chatKey, widget.identity.fipId);
  }

  void _startReadPoll() {
    Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!_alive) { t.cancel(); return; }
      final status = await KnkApi.getReadStatus(widget.contact.serverUrl, _chatKey);
      if (_alive && mounted) setState(() => _readStatus = status);
    });
  }

  @override
  void dispose() {
    _alive = false;
    _typingDebounce?.cancel();
    _typingPollTimer?.cancel();
    _draftCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    while (_alive) {
      await OfflineQueue.instance.flush();
      if (mounted) setState(() {});
      final raw = await KnkApi.getMessages(_chatKey, receiverServerUrl: widget.myServerUrl);
      final reactions = await KnkApi.getChatReactions(widget.myServerUrl, _chatKey);
      final msgs = <_DisplayMessage>[];
      for (final m in raw) {
        String text = m['text'] as String? ?? '';
        final deleted = m['deleted'] == true;
        final edited = m['edited'] == true;
        if (!deleted && _sharedKey != null) {
          try { text = await e2eDecrypt(text, _sharedKey!); } catch (_) {}
        }
        final msgIdVal = m['msgId'] as String? ?? '';
        final msgReactions = reactions[msgIdVal] as Map<String, dynamic>? ?? {};
        final parsedReactions = msgReactions.map((k, v) => MapEntry(k, List<String>.from(v as List)));
        final replyTo = m['replyTo'] as Map<String, dynamic>?;
        msgs.add(_DisplayMessage(
          msgId: msgIdVal,
          from: m['from'] as String,
          text: text,
          ts: m['ts'] as int,
          delivered: true,
          deleted: deleted,
          edited: edited,
          reactions: parsedReactions,
          replyTo: replyTo,
        ));
      }
      if (_alive && mounted) {
        final newCount = msgs.length;
        if (newCount > _prevMsgCount && _prevMsgCount > 0) {
          HapticFeedback.mediumImpact();
        }
        _prevMsgCount = newCount;
        setState(() => _messages = msgs);
        _scrollToBottom();
      }
      await KnkApi.markRead(widget.myServerUrl, _chatKey, widget.identity.fipId);
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _pollContactStatus() async {
    while (_alive) {
      final active = await KnkApi.isActive(widget.contact.serverUrl, widget.contact.fipId);
      if (_alive && mounted && active != _contactActive) setState(() => _contactActive = active);
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  void _startTypingPoll() {
    _typingPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final typingList = await KnkApi.getTyping(widget.myServerUrl, _chatKey);
      final contactTyping = typingList.any((t) => t['fipId'] == widget.contact.fipId);
      if (mounted && contactTyping != _contactTyping) setState(() => _contactTyping = contactTyping);
    });
  }

  void _onTextChanged(String value) {
    if (_inputError != null) setState(() => _inputError = null);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 400), () {
      if (value.isNotEmpty) KnkApi.sendTyping(widget.myServerUrl, _chatKey, widget.identity.fipId);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    if (_isBlocked) return;
    final raw = _draftCtrl.text;

    // Düzenleme modu
    if (_editingMsgId != null) {
      final msgId = _editingMsgId!;
      setState(() { _editingMsgId = null; _draftCtrl.clear(); });
      await KnkApi.editMessage(widget.myServerUrl, _chatKey, msgId, raw);
      await KnkApi.editMessage(widget.contact.serverUrl, _chatKey, msgId, raw);
      return;
    }

    final error = validateMessage(raw);
    if (error != null) { setState(() => _inputError = error); return; }
    final text = sanitizeMessage(raw);
    setState(() => _inputError = null);

    if (!_contactActive) {
      final active = await KnkApi.isActive(widget.contact.serverUrl, widget.contact.fipId);
      if (!active) { if (mounted) { setState(() => _contactActive = false); _showDeactivatedDialog(); } return; }
      setState(() => _contactActive = true);
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    String encryptedText = text;
    if (_sharedKey != null) {
      try { encryptedText = await e2eEncrypt(text, _sharedKey!); } catch (_) {}
    }

    final replyData = _replyToMsg != null
        ? {'msgId': _replyToMsg!['msgId'], 'from': _replyToMsg!['from'], 'text': _replyToMsg!['text']}
        : null;
    setState(() { _replyToMsg = null; });

    try {
      final (ok, myMsgId) = await KnkApi.sendMessage(
          receiverServerUrl: widget.myServerUrl, chatKey: _chatKey,
          from: widget.identity.fipId, text: encryptedText, ts: ts, replyTo: replyData);
      if (!ok) throw const SocketException('Server unreachable');

      final newMsg = _DisplayMessage(
          msgId: myMsgId ?? '', from: widget.identity.fipId, text: text,
          ts: ts, delivered: false, deleted: false, edited: false, replyTo: replyData);
      setState(() { _messages.add(newMsg); _draftCtrl.clear(); });
      _scrollToBottom();

      final (deliveredToContact, _) = await KnkApi.sendMessage(
          receiverServerUrl: widget.contact.serverUrl, chatKey: _chatKey,
          from: widget.identity.fipId, text: encryptedText, ts: ts, replyTo: replyData,
          toFipId: widget.contact.fipId, senderName: _myDisplayName.isNotEmpty ? _myDisplayName : widget.identity.fipId);

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.ts == ts && m.from == widget.identity.fipId);
          if (idx != -1) {
            _messages[idx] = _DisplayMessage(
              msgId: _messages[idx].msgId, from: _messages[idx].from, text: _messages[idx].text,
              ts: _messages[idx].ts, delivered: deliveredToContact, deleted: false, edited: false,
              replyTo: _messages[idx].replyTo,
            );
          }
        });
      }
    } on SocketException {
      await _enqueueOffline(encryptedText, ts, replyData, text);
    } on TimeoutException {
      await _enqueueOffline(encryptedText, ts, replyData, text);
    }
  }

  Future<void> _enqueueOffline(String encryptedText, int ts, Map<String, dynamic>? replyData, String plainText) async {
    await OfflineQueue.instance.enqueue(QueuedMessage(
      chatKey: _chatKey, receiverServerUrl: widget.myServerUrl,
      from: widget.identity.fipId, text: encryptedText, ts: ts,
      replyToMsgId: replyData?['msgId'] as String?,
      replyToFrom: replyData?['from'] as String?,
      replyToText: replyData?['text'] as String?,
    ));
    await OfflineQueue.instance.enqueue(QueuedMessage(
      chatKey: _chatKey, receiverServerUrl: widget.contact.serverUrl,
      from: widget.identity.fipId, text: encryptedText, ts: ts,
      replyToMsgId: replyData?['msgId'] as String?,
      replyToFrom: replyData?['from'] as String?,
      replyToText: replyData?['text'] as String?,
      toFipId: widget.contact.fipId,
      senderName: _myDisplayName.isNotEmpty ? _myDisplayName : widget.identity.fipId,
    ));
    if (mounted) setState(() { _draftCtrl.clear(); });
  }

  Widget _buildMessageList() {
    final queued = OfflineQueue.instance.getForChat(_chatKey);
    // Deduplicate: only show queued messages whose ts is not already in _messages
    final existingTs = _messages.map((m) => m.ts).toSet();
    final uniqueQueued = queued.where((q) => !existingTs.contains(q.ts)).toList();
    final totalCount = _messages.length + uniqueQueued.length;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(14),
      itemCount: totalCount,
      itemBuilder: (context, i) {
        // Queued messages appear at the bottom
        if (i >= _messages.length) {
          final q = uniqueQueued[i - _messages.length];
          return _buildQueuedBubble(q);
        }
        final m = _messages[i];
        final mine = m.from == widget.identity.fipId;
        String displayText;
        if (m.deleted) {
          displayText = '\u{1F5D1} Bu mesaj silindi.';
        } else if (_filtered.containsKey(m.msgId)) {
          displayText = _filtered[m.msgId]!;
        } else {
          displayText = filterProfanity(m.text);
          if (displayText == m.text) {
            filterProfanityAsync(m.text).then((v) {
              if (v != m.text && mounted) setState(() => _filtered[m.msgId] = v);
            });
          } else {
            _filtered[m.msgId] = displayText;
          }
        }
        final isLastMine = mine && i == _messages.lastIndexWhere((x) => x.from == widget.identity.fipId);
        return GestureDetector(
          onLongPress: () => _onLongPressMessage(m),
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  decoration: BoxDecoration(
                    color: m.deleted ? KnkColors.panelAlt : (mine ? KnkColors.accent : KnkColors.panel),
                    border: (mine && !m.deleted) ? null : Border.all(color: KnkColors.line),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(mine ? 12 : 2), bottomRight: Radius.circular(mine ? 2 : 12),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (m.replyTo != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFF06251A).withOpacity(0.3) : KnkColors.panelAlt,
                          borderRadius: BorderRadius.circular(6),
                          border: Border(left: BorderSide(color: KnkColors.accent, width: 3)),
                        ),
                        child: Text(m.replyTo!['text'] as String? ?? '',
                          style: TextStyle(color: mine ? const Color(0xFF06251A) : KnkColors.textDim, fontSize: 11),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    Text(displayText,
                      style: TextStyle(
                        color: m.deleted ? KnkColors.textDim : (mine ? const Color(0xFF06251A) : KnkColors.text),
                        fontSize: 13.5, height: 1.45,
                        fontStyle: m.deleted ? FontStyle.italic : FontStyle.normal,
                      )),
                    if (_translating.contains(m.msgId))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: KnkColors.textDim)),
                      ),
                    if (_translations.containsKey(m.msgId))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('çeviri', style: TextStyle(color: KnkColors.textDim, fontSize: 9, fontStyle: FontStyle.italic)),
                          const SizedBox(height: 2),
                          Text(_translations[m.msgId]!,
                            style: TextStyle(
                              color: (mine ? const Color(0xFF06251A) : KnkColors.text).withOpacity(0.8),
                              fontSize: 13, height: 1.4, fontStyle: FontStyle.italic,
                            )),
                        ]),
                      ),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (m.edited && !m.deleted)
                        Text('d\u00FCzenlendi \u00B7 ', style: TextStyle(color: (mine ? const Color(0xFF06251A) : KnkColors.text).withOpacity(0.5), fontSize: 9)),
                      Text(_formatTime(m.ts), style: TextStyle(color: (mine ? const Color(0xFF06251A) : KnkColors.text).withOpacity(0.6), fontSize: 9.5)),
                      if (mine && !m.deleted) ...[
                        const SizedBox(width: 4),
                        Text(
                          isLastMine && _contactRead ? '\u2713\u2713' : (m.delivered ? '\u2713\u2713' : '\u2713'),
                          style: TextStyle(
                            color: isLastMine && _contactRead ? Colors.lightBlueAccent : const Color(0xFF06251A).withOpacity(0.7),
                            fontSize: 9.5,
                            fontWeight: isLastMine && _contactRead ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ]),
                  ]),
                ),
                if (m.reactions.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Wrap(spacing: 4, runSpacing: 4,
                      children: m.reactions.entries.map((e) => GestureDetector(
                        onTap: () {
                          KnkApi.reactMessage(widget.myServerUrl, _chatKey, m.msgId, widget.identity.fipId, e.key);
                          KnkApi.reactMessage(widget.contact.serverUrl, _chatKey, m.msgId, widget.identity.fipId, e.key);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: KnkColors.panelAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: KnkColors.line)),
                          child: Text('${e.key} ${e.value.length}', style: const TextStyle(fontSize: 11)),
                        ),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueuedBubble(QueuedMessage q) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: KnkColors.accent.withOpacity(0.5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
            bottomLeft: const Radius.circular(12), bottomRight: const Radius.circular(2),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(q.text, style: TextStyle(color: const Color(0xFF06251A), fontSize: 13.5, height: 1.45)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_formatTime(q.ts), style: TextStyle(color: const Color(0xFF06251A).withOpacity(0.6), fontSize: 9.5)),
            const SizedBox(width: 4),
            Icon(Icons.access_time, color: const Color(0xFF06251A).withOpacity(0.7), size: 11),
          ]),
        ]),
      ),
    );
  }

  void _onLongPressMessage(_DisplayMessage m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KnkColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Emoji reaction row
        Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['👍','❤️','😂','😮','😢','😡'].map((emoji) => GestureDetector(
              onTap: () {
                Navigator.pop(context);
                KnkApi.reactMessage(widget.myServerUrl, _chatKey, m.msgId, widget.identity.fipId, emoji);
                KnkApi.reactMessage(widget.contact.serverUrl, _chatKey, m.msgId, widget.identity.fipId, emoji);
              },
              child: Text(emoji, style: const TextStyle(fontSize: 30)),
            )).toList(),
          ),
        ),
        Divider(color: KnkColors.line, height: 1),
        ListTile(
          leading: Icon(Icons.reply, color: KnkColors.accent),
          title: Text('Yanıtla', style: TextStyle(color: KnkColors.text)),
          onTap: () {
            Navigator.pop(context);
            setState(() => _replyToMsg = {'msgId': m.msgId, 'from': m.from, 'text': m.text});
          },
        ),
        if (!m.deleted)
          ListTile(
            leading: Icon(Icons.translate, color: KnkColors.accent),
            title: Text('Çevir', style: TextStyle(color: KnkColors.text)),
            onTap: () {
              Navigator.pop(context);
              _translateMessage(m.msgId, m.text);
            },
          ),
        if (m.from == widget.identity.fipId && !m.deleted) ...[
          ListTile(
            leading: Icon(Icons.edit, color: KnkColors.accent),
            title: Text('Düzenle', style: TextStyle(color: KnkColors.text)),
            onTap: () { Navigator.pop(context); setState(() { _editingMsgId = m.msgId; _draftCtrl.text = m.text; }); },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: KnkColors.danger),
            title: Text('Sil', style: TextStyle(color: KnkColors.danger)),
            onTap: () async {
              Navigator.pop(context);
              await KnkApi.deleteMessage(widget.myServerUrl, _chatKey, m.msgId);
              await KnkApi.deleteMessage(widget.contact.serverUrl, _chatKey, m.msgId);
            },
          ),
        ],
      ])),
    );
  }

  Future<void> _translateMessage(String msgId, String text) async {
    if (_translations.containsKey(msgId)) {
      setState(() => _translations.remove(msgId));
      return;
    }
    setState(() => _translating.add(msgId));
    final translated = await TranslateService.translate(text);
    if (mounted) {
      setState(() {
        _translating.remove(msgId);
        if (translated != text) _translations[msgId] = translated;
      });
    }
  }

  bool get _contactRead => _readStatus.containsKey(widget.contact.fipId);

  void _showDeactivatedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: Text('Kişi artık aktif değil', style: TextStyle(color: KnkColors.text, fontSize: 15)),
        content: Text('Bu kişi hesabını bu cihazdan kaldırdı.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Tamam', style: TextStyle(color: KnkColors.accent)))],
      ),
    );
  }

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildAvatar(String name, String avatar, {double size = 36}) {
    if (avatar.isNotEmpty) {
      try {
        final bytes = base64Decode(avatar);
        return CircleAvatar(radius: size / 2, backgroundImage: MemoryImage(bytes));
      } catch (_) {}
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: KnkColors.accent.withOpacity(0.2),
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: KnkColors.accent, fontSize: size * 0.4, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          _buildAvatar(widget.contact.name, widget.contact.avatar, size: 32),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.contact.name, style: const TextStyle(fontSize: 15)),
            if (widget.contact.statusMsg.isNotEmpty)
              Text(widget.contact.statusMsg, style: TextStyle(color: KnkColors.textDim, fontSize: 10)),
          ]),
        ]),
      ),
      body: Stack(children: [
        ChatWallpaper.buildBackground(),
        Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KnkColors.line))),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('FIP · ${widget.contact.code}', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1)),
              if (_sharedKey != null) ...[SizedBox(width: 8), Icon(Icons.lock, color: KnkColors.accent, size: 11)],
            ]),
          ),
          if (_isBlocked)
            _banner(Icons.block, 'Bu kişiyi engellediniz.', KnkColors.danger)
          else if (!_contactActive)
            _banner(Icons.info_outline, '${widget.contact.name} hesabını kaldırdı.', KnkColors.danger),
          if (_contactTyping && !_isBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('${widget.contact.name} yazıyor…', style: TextStyle(color: KnkColors.textDim, fontSize: 11, fontStyle: FontStyle.italic)),
            ),
          if (_editingMsgId != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: KnkColors.accent.withOpacity(0.1),
              child: Row(children: [
                Icon(Icons.edit, color: KnkColors.accent, size: 14),
                const SizedBox(width: 8),
                Text('Düzenleme modu', style: TextStyle(color: KnkColors.accent, fontSize: 12)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() { _editingMsgId = null; _draftCtrl.clear(); }),
                  child: Icon(Icons.close, color: KnkColors.textDim, size: 16),
                ),
              ]),
            ),
          Expanded(
            child: _isBlocked
                ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Bu kişiyi engellediniz.\nMesajlarını görmek için engeli kaldırın.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6))))
                : (_messages.isEmpty && OfflineQueue.instance.getForChat(_chatKey).isEmpty)
                    ? Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text('Bu sohbet temiz. İlk mesajı sen gönder.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6))))
                    : _buildMessageList(),
          ),
          if (_inputError != null)
            Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: KnkColors.danger.withOpacity(0.1), child: Text(_inputError!, style: TextStyle(color: KnkColors.danger, fontSize: 12))),
          // Reply banner
          if (_replyToMsg != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: KnkColors.accent.withOpacity(0.1),
              child: Row(children: [
                Container(width: 3, height: 36, decoration: BoxDecoration(color: KnkColors.accent, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_replyToMsg!['from'] == widget.identity.fipId ? 'Sen' : widget.contact.name,
                    style: TextStyle(color: KnkColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(_replyToMsg!['text'] as String, style: TextStyle(color: KnkColors.textDim, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                GestureDetector(onTap: () => setState(() => _replyToMsg = null), child: Icon(Icons.close, color: KnkColors.textDim, size: 16)),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border(top: BorderSide(color: KnkColors.line))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _draftCtrl,
                  style: TextStyle(color: KnkColors.text, fontSize: 14),
                  enabled: !_isBlocked,
                  decoration: InputDecoration(
                    hintText: _isBlocked ? 'Bu kişiyi engellediniz.' : (_editingMsgId != null ? 'Mesajı düzenle…' : (_contactActive ? 'Mesaj yaz…' : 'Kişi artık aktif değil…')),
                    hintStyle: TextStyle(color: KnkColors.textDim),
                    filled: true, fillColor: KnkColors.bg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: KnkColors.line)),
                  ),
                  onChanged: _onTextChanged,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _isBlocked ? null : _send,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40, height: 40, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (_isBlocked || !_contactActive) ? KnkColors.line : KnkColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _editingMsgId != null ? Icons.check : Icons.arrow_upward,
                    color: (_isBlocked || !_contactActive) ? KnkColors.textDim : const Color(0xFF06251A),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
      ]),
    );
  }

  Widget _banner(IconData icon, String text, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: color.withOpacity(0.12),
    child: Row(children: [Icon(icon, color: color, size: 16), const SizedBox(width: 8), Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 11.5, height: 1.4)))]),
  );
}

class _DisplayMessage {
  final String msgId;
  final String from;
  final String text;
  final int ts;
  final bool delivered;
  final bool deleted;
  final bool edited;
  final Map<String, List<String>> reactions;
  final Map<String, dynamic>? replyTo;
  _DisplayMessage({required this.msgId, required this.from, required this.text, required this.ts, required this.delivered, required this.deleted, required this.edited, this.reactions = const {}, this.replyTo});
}
