import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../e2e.dart';
import '../theme.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';

class ChatScreen extends StatefulWidget {
  final FipBlock identity;
  final Contact contact;
  final String myServerUrl;

  const ChatScreen({super.key, required this.identity, required this.contact, required this.myServerUrl});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _Delivery { sent, delivered }

class _ChatScreenState extends State<ChatScreen> {
  final _draftCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<_DisplayMessage> _messages = [];
  late final String _chatKey;
  bool _disposed = false;
  bool _loaded = false;
  bool _contactDeactivated = false;
  bool _serverUnreachable = false;
  String? _inputError;
  bool _contactTyping = false;
  bool _isBlocked = false;
  bool _sending = false;
  SecretKey? _sharedKey;

  Timer? _pollTimer;
  Timer? _statusTimer;
  bool _polling = false;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastKeyAttempt = DateTime.now();

  /// Ham (şifreli) metin -> çözülmüş metin. Her 2 saniyede tüm geçmişi yeniden çözmemek için.
  final Map<String, String?> _decryptCache = {};
  /// Bu oturumda gönderilen mesajların teslim durumu (ts -> durum).
  final Map<int, _Delivery> _delivery = {};
  /// Karşı tarafa henüz ulaştırılamamış mesajlar (ts -> gönderilecek metin). Her turda yeniden denenir.
  final Map<int, String> _undelivered = {};

  @override
  void initState() {
    super.initState();
    _chatKey = chatKeyFor(widget.identity.fipId, widget.contact.fipId);
    _checkBlocked();
    _initE2E().whenComplete(_poll);
    _pollContactStatus();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _statusTimer?.cancel();
    _draftCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initE2E() async {
    final stored = widget.contact.publicKey;
    if (stored != null && stored.isNotEmpty) {
      await _useKey(stored);
    }
    // Sunucudaki güncel anahtarı al (kayıtlı anahtar yoksa ya da değiştiyse).
    try {
      final info = await KnkApi.lookupByCode(widget.contact.serverUrl, widget.contact.code);
      final pubKey = info?['publicKey'] as String?;
      if (info?['fipId'] == widget.contact.fipId && pubKey != null && pubKey.isNotEmpty && pubKey != stored) {
        widget.contact.publicKey = pubKey;
        await _useKey(pubKey);
      }
    } catch (_) {}
  }

  Future<void> _useKey(String pubKey) async {
    try {
      final key = await deriveSharedKey(pubKey);
      if (_disposed) return;
      _decryptCache.clear();
      setState(() => _sharedKey = key);
    } catch (_) {}
  }

  Future<void> _checkBlocked() async {
    final blocked = await LocalStore.loadBlockList();
    if (!_disposed) setState(() => _isBlocked = blocked.contains(widget.contact.fipId));
  }

  Future<void> _poll() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      final results = await Future.wait([
        KnkApi.getMessages(_chatKey, receiverServerUrl: widget.myServerUrl),
        KnkApi.getTyping(widget.myServerUrl, _chatKey),
      ]);
      if (_disposed) return;
      final raw = results[0];
      final typingList = results[1] ?? const [];
      final typing = typingList.any((t) => t['fipId'] == widget.contact.fipId);
      if (raw == null) {
        if (!_serverUnreachable || _contactTyping) setState(() { _serverUnreachable = true; _contactTyping = false; });
      } else {
        await _applyMessages(raw, typing);
      }
      await _retryUndelivered();
      // Karşı tarafın anahtarı henüz yoksa ara ara tekrar dene (ör. uygulamayı güncelledi).
      if (_sharedKey == null && DateTime.now().difference(_lastKeyAttempt) > const Duration(seconds: 30)) {
        _lastKeyAttempt = DateTime.now();
        unawaited(_initE2E());
      }
    } catch (_) {
    } finally {
      _polling = false;
      if (!_disposed) _pollTimer = Timer(const Duration(seconds: 2), _poll);
    }
  }

  Future<void> _applyMessages(List<Map<String, dynamic>> raw, bool typing) async {
    final msgs = <_DisplayMessage>[];
    for (final m in raw) {
      final from = m['from'];
      final ts = m['ts'];
      final text = m['text'];
      if (from is! String || ts is! num || text is! String) continue;
      String? plain;
      if (_decryptCache.containsKey(text)) {
        plain = _decryptCache[text];
      } else {
        plain = await decryptChatMessage(text, _sharedKey);
        // Anahtar henüz yokken çözülemeyen mesajı önbelleğe alma; anahtar gelince tekrar denenir.
        if (plain != null || _sharedKey != null) _decryptCache[text] = plain;
      }
      msgs.add(_DisplayMessage(from: from, text: plain, ts: ts.toInt(), encrypted: isE2EMessage(text)));
    }
    if (_disposed) return;
    final changed = !_sameMessages(msgs, _messages);
    if (!changed && typing == _contactTyping && !_serverUnreachable && _loaded) return;

    final wasNearBottom = !_scrollCtrl.hasClients ||
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.offset < 120;
    final firstLoad = !_loaded;
    setState(() {
      _messages = msgs;
      _contactTyping = typing;
      _serverUnreachable = false;
      _loaded = true;
    });
    // Kullanıcı eski mesajları okuyorsa onu aşağı çekme.
    if (changed && (wasNearBottom || firstLoad)) _scrollToBottom(animate: !firstLoad);
  }

  bool _sameMessages(List<_DisplayMessage> a, List<_DisplayMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].ts != b[i].ts || a[i].from != b[i].from || a[i].text != b[i].text) return false;
    }
    return true;
  }

  Future<void> _retryUndelivered() async {
    if (_undelivered.isEmpty || _contactDeactivated) return;
    for (final entry in _undelivered.entries.toList()) {
      final ok = await KnkApi.sendMessage(
        receiverServerUrl: widget.contact.serverUrl, chatKey: _chatKey,
        from: widget.identity.fipId, text: entry.value, ts: entry.key,
      );
      if (_disposed) return;
      if (!ok) break; // sunucu hâlâ ulaşılamaz: sonraki turda tekrar dene
      _undelivered.remove(entry.key);
      setState(() => _delivery[entry.key] = _Delivery.delivered);
    }
  }

  Future<void> _pollContactStatus() async {
    if (_disposed) return;
    final status = await KnkApi.getStatus(widget.contact.serverUrl, widget.contact.fipId);
    if (_disposed) return;
    final deactivated = status == ContactStatus.deactivated;
    if (deactivated != _contactDeactivated) setState(() => _contactDeactivated = deactivated);
    _statusTimer = Timer(const Duration(seconds: 10), _pollContactStatus);
  }

  void _onTextChanged(String value) {
    if (_inputError != null) setState(() => _inputError = null);
    if (value.trim().isEmpty || _contactDeactivated) return;
    // "Yazıyor" bilgisini karşı tarafın sunucusuna en fazla 2.5 sn'de bir gönder.
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) > const Duration(milliseconds: 2500)) {
      _lastTypingSent = now;
      KnkApi.sendTyping(widget.contact.serverUrl, _chatKey, widget.identity.fipId);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (animate) {
        _scrollCtrl.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    if (_isBlocked || _sending) return;
    final raw = _draftCtrl.text;
    final error = validateMessage(raw);
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    if (_contactDeactivated) {
      _showDeactivatedDialog();
      return;
    }
    final text = sanitizeMessage(raw);
    setState(() { _inputError = null; _sending = true; });

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      String payload = text;
      final key = _sharedKey;
      if (key != null) {
        payload = await encryptChatMessage(text, key);
        _decryptCache[payload] = text;
      }

      // Önce kendi sunucumuza yaz (✓) — sohbet geçmişi buradan okunur.
      final savedOwn = await KnkApi.sendMessage(
        receiverServerUrl: widget.myServerUrl, chatKey: _chatKey,
        from: widget.identity.fipId, text: payload, ts: ts,
      );
      if (_disposed) return;
      if (!savedOwn) {
        setState(() => _inputError = 'Mesaj gönderilemedi. Sunucuna ulaşılamıyor, tekrar dene.');
        return;
      }

      // Karşı taraftaki "yazıyor…" göstergesini hemen kapat.
      _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
      unawaited(KnkApi.sendTyping(widget.contact.serverUrl, _chatKey, widget.identity.fipId, stop: true));

      setState(() {
        _messages = [..._messages, _DisplayMessage(from: widget.identity.fipId, text: text, ts: ts, encrypted: key != null)];
        _delivery[ts] = _Delivery.sent;
        _draftCtrl.clear();
      });
      _scrollToBottom();

      // Sonra karşı tarafın sunucusuna yaz (✓✓). Aynı sunucuyu kullanıyorlarsa zaten teslim edildi.
      final sameServer = widget.contact.serverUrl == widget.myServerUrl;
      final delivered = sameServer || await KnkApi.sendMessage(
        receiverServerUrl: widget.contact.serverUrl, chatKey: _chatKey,
        from: widget.identity.fipId, text: payload, ts: ts,
      );
      if (_disposed) return;
      if (delivered) {
        setState(() => _delivery[ts] = _Delivery.delivered);
      } else {
        _undelivered[ts] = payload;
      }
    } finally {
      if (!_disposed) setState(() => _sending = false);
    }
  }

  void _showDeactivatedDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: const Text('Kişi artık aktif değil', style: TextStyle(color: KnkColors.text, fontSize: 15)),
        content: const Text('Bu kişi hesabını bu cihazdan kaldırdı. Mesajın iletilemeyecek.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Tamam', style: TextStyle(color: KnkColors.accent)))],
      ),
    );
  }

  String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} $hm';
  }

  Widget _banner(IconData icon, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: KnkColors.danger.withOpacity(0.12),
    child: Row(children: [
      Icon(icon, color: KnkColors.danger, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: KnkColors.danger, fontSize: 11.5, height: 1.4))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final inputDisabled = _isBlocked || _contactDeactivated;
    return Scaffold(
      appBar: AppBar(title: Text(widget.contact.name)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: KnkColors.line))),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('FIP eşleşmesi · ${widget.contact.code}', style: const TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1)),
              if (_sharedKey != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock, color: KnkColors.accent, size: 11),
                const SizedBox(width: 3),
                const Text('uçtan uca şifreli', style: TextStyle(color: KnkColors.accent, fontSize: 10)),
              ],
            ]),
          ),
          if (_isBlocked)
            _banner(Icons.block, 'Bu kişiyi engellediniz.')
          else if (_contactDeactivated)
            _banner(Icons.info_outline, '${widget.contact.name} hesabını kaldırdı. Artık aktif değil.')
          else if (_serverUnreachable)
            _banner(Icons.cloud_off, 'Sunucuna ulaşılamıyor. Yeniden bağlanılıyor…'),
          Expanded(
            child: _isBlocked
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Bu kişiyi engellediniz.\nMesajlarını görmek için engeli kaldırın.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6),
                      ),
                    ),
                  )
                : !_loaded && _messages.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: KnkColors.accent, strokeWidth: 2))
                    : _messages.isEmpty
                        ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: Text('Bu sohbet temiz. İlk mesajı sen gönder.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6))))
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(14),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) => _buildBubble(_messages[i]),
                          ),
          ),
          if (_contactTyping && !_isBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('${widget.contact.name} yazıyor…', style: const TextStyle(color: KnkColors.textDim, fontSize: 11, fontStyle: FontStyle.italic)),
            ),
          if (_inputError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: KnkColors.danger.withOpacity(0.1),
              child: Text(_inputError!, style: const TextStyle(color: KnkColors.danger, fontSize: 12)),
            ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: KnkColors.panel, border: Border(top: BorderSide(color: KnkColors.line))),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _draftCtrl,
                    style: const TextStyle(color: KnkColors.text, fontSize: 14),
                    enabled: !inputDisabled,
                    maxLength: maxMessageLength,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: _isBlocked ? 'Bu kişiyi engellediniz.' : (_contactDeactivated ? 'Kişi artık aktif değil…' : 'Mesaj yaz…'),
                      hintStyle: const TextStyle(color: Color(0xFF5C6E6B)),
                      filled: true, fillColor: KnkColors.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: KnkColors.line)),
                    ),
                    onChanged: _onTextChanged,
                    // Enter ile gönderdikten sonra odak kutuda kalsın; art arda mesaj yazılabilsin.
                    onEditingComplete: () {},
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: (inputDisabled || _sending) ? null : _send,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40, height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: inputDisabled ? KnkColors.line : KnkColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06251A)))
                        : Icon(Icons.arrow_upward, color: inputDisabled ? KnkColors.textDim : const Color(0xFF06251A)),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_DisplayMessage m) {
    final mine = m.from == widget.identity.fipId;
    final undecryptable = m.text == null;
    final displayText = undecryptable ? '🔒 Bu şifreli mesaj çözülemedi.' : filterProfanity(m.text!);
    final fg = mine ? const Color(0xFF06251A) : KnkColors.text;
    final status = _delivery[m.ts];
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: mine ? KnkColors.accent : KnkColors.panel,
          border: mine ? null : Border.all(color: KnkColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(mine ? 12 : 2), bottomRight: Radius.circular(mine ? 2 : 12),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(displayText, style: TextStyle(
            color: undecryptable ? fg.withOpacity(0.6) : fg, fontSize: 13.5, height: 1.45,
            fontStyle: undecryptable ? FontStyle.italic : FontStyle.normal,
          )),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatTime(m.ts), style: TextStyle(color: fg.withOpacity(0.6), fontSize: 9.5)),
              if (mine) ...[
                const SizedBox(width: 4),
                // Geçmişten gelen (bu oturumda gönderilmemiş) mesajlar teslim edilmiş sayılır.
                Text(status == _Delivery.sent ? '✓' : '✓✓', style: TextStyle(color: fg.withOpacity(0.7), fontSize: 9.5)),
              ],
            ],
          ),
        ]),
      ),
    );
  }
}

class _DisplayMessage {
  final String from;
  /// Çözülemeyen şifreli mesajlar için null.
  final String? text;
  final int ts;
  final bool encrypted;
  _DisplayMessage({required this.from, required this.text, required this.ts, required this.encrypted});
}
