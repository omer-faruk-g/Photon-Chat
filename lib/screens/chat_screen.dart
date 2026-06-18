import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../e2e.dart';
import '../theme.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';
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
  bool _alive = true;
  bool _contactActive = true;
  String? _inputError;
  bool _contactTyping = false;
  bool _isBlocked = false;
  SecretKey? _sharedKey;
  String? _editingMsgId;
  Map<String, dynamic> _readStatus = {};

  Timer? _typingDebounce;
  Timer? _typingPollTimer;

  @override
  void initState() {
    super.initState();
    _chatKey = chatKeyFor(widget.identity.fipId, widget.contact.fipId);
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
      final raw = await KnkApi.getMessages(_chatKey, receiverServerUrl: widget.myServerUrl);
      final msgs = <_DisplayMessage>[];
      for (final m in raw) {
        String text = m['text'] as String? ?? '';
        final deleted = m['deleted'] == true;
        final edited = m['edited'] == true;
        if (!deleted && _sharedKey != null) {
          try { text = await e2eDecrypt(text, _sharedKey!); } catch (_) {}
        }
        msgs.add(_DisplayMessage(
          msgId: m['msgId'] as String? ?? '',
          from: m['from'] as String,
          text: text,
          ts: m['ts'] as int,
          delivered: true,
          deleted: deleted,
          edited: edited,
        ));
      }
      if (_alive && mounted) {
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

    final (_, myMsgId) = await KnkApi.sendMessage(receiverServerUrl: widget.myServerUrl, chatKey: _chatKey, from: widget.identity.fipId, text: encryptedText, ts: ts);

    final newMsg = _DisplayMessage(msgId: myMsgId ?? '', from: widget.identity.fipId, text: text, ts: ts, delivered: false, deleted: false, edited: false);
    setState(() { _messages.add(newMsg); _draftCtrl.clear(); });
    _scrollToBottom();

    final (deliveredToContact, _) = await KnkApi.sendMessage(receiverServerUrl: widget.contact.serverUrl, chatKey: _chatKey, from: widget.identity.fipId, text: encryptedText, ts: ts);

    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.ts == ts && m.from == widget.identity.fipId);
        if (idx != -1) {
          _messages[idx] = _DisplayMessage(
            msgId: _messages[idx].msgId, from: _messages[idx].from, text: _messages[idx].text,
            ts: _messages[idx].ts, delivered: deliveredToContact, deleted: false, edited: false,
          );
        }
      });
    }
  }

  void _onLongPressMessage(_DisplayMessage m) {
    if (m.from != widget.identity.fipId || m.deleted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: KnkColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit, color: KnkColors.accent),
            title: const Text('Düzenle', style: TextStyle(color: KnkColors.text)),
            onTap: () {
              Navigator.pop(context);
              setState(() { _editingMsgId = m.msgId; _draftCtrl.text = m.text; });
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: KnkColors.danger),
            title: const Text('Sil', style: TextStyle(color: KnkColors.danger)),
            onTap: () async {
              Navigator.pop(context);
              await KnkApi.deleteMessage(widget.myServerUrl, _chatKey, m.msgId);
              await KnkApi.deleteMessage(widget.contact.serverUrl, _chatKey, m.msgId);
            },
          ),
        ]),
      ),
    );
  }

  bool get _contactRead => _readStatus.containsKey(widget.contact.fipId);

  void _showDeactivatedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: const Text('Kişi artık aktif değil', style: TextStyle(color: KnkColors.text, fontSize: 15)),
        content: const Text('Bu kişi hesabını bu cihazdan kaldırdı.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam', style: TextStyle(color: KnkColors.accent)))],
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
              Text(widget.contact.statusMsg, style: const TextStyle(color: KnkColors.textDim, fontSize: 10)),
          ]),
        ]),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: KnkColors.line))),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('FIP · ${widget.contact.code}', style: const TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1)),
              if (_sharedKey != null) ...[const SizedBox(width: 8), const Icon(Icons.lock, color: KnkColors.accent, size: 11)],
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
              child: Text('${widget.contact.name} yazıyor…', style: const TextStyle(color: KnkColors.textDim, fontSize: 11, fontStyle: FontStyle.italic)),
            ),
          if (_editingMsgId != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: KnkColors.accent.withOpacity(0.1),
              child: Row(children: [
                const Icon(Icons.edit, color: KnkColors.accent, size: 14),
                const SizedBox(width: 8),
                const Text('Düzenleme modu', style: TextStyle(color: KnkColors.accent, fontSize: 12)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() { _editingMsgId = null; _draftCtrl.clear(); }),
                  child: const Icon(Icons.close, color: KnkColors.textDim, size: 16),
                ),
              ]),
            ),
          Expanded(
            child: _isBlocked
                ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Bu kişiyi engellediniz.\nMesajlarını görmek için engeli kaldırın.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6))))
                : _messages.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: Text('Bu sohbet temiz. İlk mesajı sen gönder.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6))))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(14),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final mine = m.from == widget.identity.fipId;
                          final displayText = m.deleted ? '🗑 Bu mesaj silindi.' : filterProfanity(m.text);
                          final isLastMine = mine && i == _messages.lastIndexWhere((x) => x.from == widget.identity.fipId);
                          return GestureDetector(
                            onLongPress: () => _onLongPressMessage(m),
                            child: Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
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
                                  Text(displayText,
                                    style: TextStyle(
                                      color: m.deleted ? KnkColors.textDim : (mine ? const Color(0xFF06251A) : KnkColors.text),
                                      fontSize: 13.5, height: 1.45,
                                      fontStyle: m.deleted ? FontStyle.italic : FontStyle.normal,
                                    )),
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    if (m.edited && !m.deleted)
                                      Text('düzenlendi · ', style: TextStyle(color: (mine ? const Color(0xFF06251A) : KnkColors.text).withOpacity(0.5), fontSize: 9)),
                                    Text(_formatTime(m.ts), style: TextStyle(color: (mine ? const Color(0xFF06251A) : KnkColors.text).withOpacity(0.6), fontSize: 9.5)),
                                    if (mine && !m.deleted) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        isLastMine && _contactRead ? '✓✓' : (m.delivered ? '✓✓' : '✓'),
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
                            ),
                          );
                        },
                      ),
          ),
          if (_inputError != null)
            Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: KnkColors.danger.withOpacity(0.1), child: Text(_inputError!, style: const TextStyle(color: KnkColors.danger, fontSize: 12))),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: KnkColors.panel, border: Border(top: BorderSide(color: KnkColors.line))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _draftCtrl,
                  style: const TextStyle(color: KnkColors.text, fontSize: 14),
                  enabled: !_isBlocked,
                  decoration: InputDecoration(
                    hintText: _isBlocked ? 'Bu kişiyi engellediniz.' : (_editingMsgId != null ? 'Mesajı düzenle…' : (_contactActive ? 'Mesaj yaz…' : 'Kişi artık aktif değil…')),
                    hintStyle: const TextStyle(color: Color(0xFF5C6E6B)),
                    filled: true, fillColor: KnkColors.bg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: KnkColors.line)),
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
  _DisplayMessage({required this.msgId, required this.from, required this.text, required this.ts, required this.delivered, required this.deleted, required this.edited});
}
