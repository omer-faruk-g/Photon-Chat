import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../e2e.dart';
import '../theme.dart';
import '../widgets.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';
import 'verify_key_screen.dart';

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
  KeyTrust _trust = KeyTrust.none;

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
      // Anahtar sabitleme: ilk öğrenilen anahtar kullanılır ve sunucudaki bir değişiklikle
      // sessizce değiştirilmez (ortadaki adam saldırısına karşı). Bir fipId'nin anahtarı
      // meşru olarak değişmez; hesap silinip yeniden açılınca fipId de değişir.
      await _useKey(stored);
      return;
    }
    try {
      final info = await KnkApi.lookupByCode(widget.contact.serverUrl, widget.contact.code);
      final pubKey = info?['publicKey'] as String?;
      if (info?['fipId'] == widget.contact.fipId && pubKey != null && pubKey.isNotEmpty) {
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
      await _loadTrust();
    } catch (_) {}
  }

  Future<void> _loadTrust() async {
    final verified = await LocalStore.loadVerifiedKeys();
    if (_disposed) return;
    setState(() => _trust = keyTrust(verified, widget.contact.fipId, widget.contact.publicKey));
  }

  Future<void> _openVerify() async {
    final pub = widget.contact.publicKey;
    if (pub == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kişinin şifreleme anahtarı henüz alınmadı. Biraz sonra tekrar dene.'), duration: Duration(seconds: 3)));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VerifyKeyScreen(
      myFipId: widget.identity.fipId, theirFipId: widget.contact.fipId, theirName: widget.contact.name, theirPublicKey: pub,
    )));
    await _loadTrust();
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

  Widget _banner(IconData icon, String text, {Color tone = KnkColors.danger}) => NoticeBar(icon: icon, text: text, tone: tone);

  IconData get _trustIcon => switch (_trust) {
    KeyTrust.verified => Icons.verified_user_outlined,
    KeyTrust.changed => Icons.gpp_bad_outlined,
    _ => Icons.gpp_maybe_outlined,
  };

  Color get _trustColor => switch (_trust) {
    KeyTrust.verified => KnkColors.accent,
    KeyTrust.changed => KnkColors.danger,
    _ => KnkColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    final inputDisabled = _isBlocked || _contactDeactivated;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.contact.name, overflow: TextOverflow.ellipsis),
          Text('kod ${widget.contact.code}', style: KnkText.meta.merge(KnkText.tabular)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Güvenlik numarası',
            onPressed: _openVerify,
            icon: Icon(_trustIcon, color: _trustColor),
          ),
          const SizedBox(width: Space.s1),
        ],
      ),
      body: Column(
        children: [
          if (_sharedKey != null)
            Material(
              color: KnkColors.accentWash,
              child: InkWell(
                onTap: _openVerify,
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
                    child: Row(children: [
                      const Icon(Icons.lock_outline, color: KnkColors.accent, size: 16),
                      const SizedBox(width: Space.s1),
                      const Text('uçtan uca şifreli', style: TextStyle(color: KnkColors.accent, fontSize: 13)),
                      const Spacer(),
                      Icon(_trustIcon, color: _trust == KeyTrust.verified ? KnkColors.accent : KnkColors.accent2, size: 16),
                      const SizedBox(width: Space.s1),
                      Text(
                        _trust == KeyTrust.verified ? 'doğrulandı' : 'güvenlik numarasını doğrula',
                        style: TextStyle(
                          color: _trust == KeyTrust.verified ? KnkColors.accent : KnkColors.accent2, fontSize: 13,
                          decoration: _trust == KeyTrust.verified ? null : TextDecoration.underline,
                          decorationColor: KnkColors.accent2,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          if (_isBlocked)
            _banner(Icons.block, 'Bu kişiyi engelledin.')
          else if (_contactDeactivated)
            _banner(Icons.person_off_outlined, '${widget.contact.name} hesabını kaldırdı. Mesajların artık ona ulaşmaz.')
          else if (_trust == KeyTrust.changed)
            _banner(Icons.gpp_bad_outlined, '${widget.contact.name} için doğruladığın anahtar değişti. Güvenlik numarasını yeniden karşılaştır.', )
          else if (_serverUnreachable)
            _banner(Icons.cloud_off_outlined, 'Sunucuna ulaşılamıyor. Yeniden bağlanılıyor…', tone: KnkColors.accent2),
          Expanded(
            child: _isBlocked
                ? const CenterNote(icon: Icons.block, title: 'Bu kişiyi engelledin.', body: 'Mesajlarını görmek için engeli kaldırman gerekir.')
                : !_loaded && _messages.isEmpty
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _messages.isEmpty
                        ? const CenterNote(icon: Icons.forum_outlined, title: 'Bu sohbet temiz.', body: 'İlk mesajı sen gönder.')
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(vertical: Space.s2),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) => ContentWidth(child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                              child: _buildBubble(_messages[i]),
                            )),
                          ),
          ),
          if (_contactTyping && !_isBlocked)
            ContentWidth(child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s1),
              child: Align(alignment: Alignment.centerLeft, child: Text('${widget.contact.name} yazıyor…', style: KnkText.small.copyWith(fontStyle: FontStyle.italic))),
            )),
          if (_inputError != null) _banner(Icons.error_outline, _inputError!),
          MessageComposer(
            controller: _draftCtrl,
            enabled: !inputDisabled,
            sending: _sending,
            hint: _isBlocked ? 'Bu kişiyi engelledin' : (_contactDeactivated ? 'Kişi artık aktif değil' : 'Mesaj yaz'),
            onChanged: _onTextChanged,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_DisplayMessage m) {
    final mine = m.from == widget.identity.fipId;
    final undecryptable = m.text == null;
    // Şifreli bir sohbette karşı taraftan gelen düz metin mesaj doğrulanamaz
    // (eski sürümden gönderilmiş ya da başkası tarafından eklenmiş olabilir).
    final unverified = !mine && !m.encrypted && _sharedKey != null;
    final fg = mine ? KnkColors.onAccent : KnkColors.text;
    final status = _delivery[m.ts];
    final maxW = (MediaQuery.sizeOf(context).width * 0.78).clamp(0.0, 520.0);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.s1),
        padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s2, Space.s1),
        constraints: BoxConstraints(maxWidth: maxW),
        decoration: BoxDecoration(
          color: mine ? KnkColors.accent : KnkColors.panel,
          border: mine ? null : Border.all(color: KnkColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(KnkRadius.bubble), topRight: const Radius.circular(KnkRadius.bubble),
            bottomLeft: Radius.circular(mine ? KnkRadius.bubble : 2), bottomRight: Radius.circular(mine ? 2 : KnkRadius.bubble),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (undecryptable)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 16, color: fg.withOpacity(0.7)),
              const SizedBox(width: Space.s1),
              Flexible(child: Text('Bu şifreli mesaj çözülemedi.', style: TextStyle(color: fg.withOpacity(0.7), fontSize: 15, fontStyle: FontStyle.italic))),
            ])
          else
            Text(filterProfanity(m.text!), style: TextStyle(color: fg, fontSize: 15, height: 1.45)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unverified) ...[
                const Tooltip(
                  message: 'Bu mesaj şifresiz geldi; gerçekten bu kişiden geldiği doğrulanamıyor.',
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber_outlined, size: 14, color: KnkColors.accent2),
                    SizedBox(width: Space.s1),
                    Text('şifresiz', style: TextStyle(color: KnkColors.accent2, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: Space.s1),
              ],
              Text(_formatTime(m.ts), style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11).merge(KnkText.tabular)),
              if (mine) ...[
                const SizedBox(width: Space.s1),
                // Geçmişten gelen (bu oturumda gönderilmemiş) mesajlar teslim edilmiş sayılır.
                Tooltip(
                  message: status == _Delivery.sent ? 'Sunucuna yazıldı, karşı tarafa iletiliyor' : 'Karşı tarafa iletildi',
                  child: Icon(status == _Delivery.sent ? Icons.done : Icons.done_all, size: 14, color: fg.withOpacity(0.8)),
                ),
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
