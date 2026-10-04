import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../e2e.dart';
import '../theme.dart';
import '../widgets.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';
import 'verify_key_screen.dart';

/// Kullanıcının bu gruptaki durumu.
enum _Membership { loading, member, pending, removed, groupGone, legacy }

/// Grup sohbeti. Grubun tüm verisi grup sahibinin sunucusunda tutulur; tüm üyeler
/// oradan okur ve oraya yazar. Ekran kapanırken grup bırakıldıysa `true` döner.
class GroupChatScreen extends StatefulWidget {
  final Group group;
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  const GroupChatScreen({super.key, required this.group, required this.identity, required this.displayName, required this.myServerUrl});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _pendingJoins = [];
  List<String> _mutedMembers = [];
  Timer? _msgTimer;
  Timer? _infoTimer;
  bool _disposed = false;
  bool _msgPolling = false;
  bool _infoPolling = false;
  bool _loaded = false;
  bool _sending = false;
  bool _unreachable = false;
  String? _inputError;
  _Membership _membership = _Membership.loading;

  /// Ham (şifreli) metin -> çözülmüş metin. Her turda tüm geçmişi yeniden çözmemek için.
  final Map<String, String?> _decryptCache = {};
  /// Anahtar halkası değişti: mesajlar yeniden çözülmeli.
  bool _keysChanged = false;
  /// Bir üyeye anahtar teslimi sürüyor (aynı anda iki kez sarmamak için).
  final Set<String> _wrapping = {};
  /// Doğrulanmış anahtarlar (fipId -> public key).
  Map<String, String> _verifiedKeys = {};

  Group get _g => widget.group;
  String get _owner => _g.ownerServerUrl;
  String get _me => widget.identity.fipId;
  String get _token => _g.token ?? '';

  @override
  void initState() {
    super.initState();
    if (_g.token == null) {
      // Güncellemeden önce oluşturulmuş/katılınmış grup: yetki anahtarı yok.
      _membership = _Membership.legacy;
      _loaded = true;
      return;
    }
    if (_g.isOwner) _membership = _Membership.member;
    _loadVerified();
    _pollInfo();
    _pollMessages();
  }

  @override
  void dispose() {
    _disposed = true;
    _msgTimer?.cancel();
    _infoTimer?.cancel();
    _toastTimer?.cancel();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // --- Polling ---

  Future<void> _pollMessages() async {
    if (_disposed || _msgPolling) return;
    _msgPolling = true;
    try {
      final msgs = await KnkApi.getGroupMessages(_owner, _g.groupId, _token);
      if (_disposed) return;
      if (msgs == null) {
        if (!_unreachable) setState(() => _unreachable = true);
      } else {
        msgs.removeWhere((m) => m['ts'] is! num || m['from'] is! String || m['text'] is! String);
        msgs.sort((a, b) => (a['ts'] as num).compareTo(b['ts'] as num));
        final keysChanged = _keysChanged;
        _keysChanged = false;
        for (final m in msgs) {
          final raw = m['text'] as String;
          m['_enc'] = isGroupE2EMessage(raw);
          if (_decryptCache.containsKey(raw)) {
            m['_plain'] = _decryptCache[raw];
          } else {
            final plain = await decryptGroupMessage(raw, _g.keyring);
            // Anahtarı henüz gelmemiş mesajı önbelleğe alma; anahtar gelince tekrar denenir.
            if (plain != null || _g.keyring.containsKey(groupMessageKeyId(raw))) _decryptCache[raw] = plain;
            m['_plain'] = plain;
          }
        }
        if (_disposed) return;
        final changed = keysChanged || msgs.length != _messages.length ||
            (msgs.isNotEmpty && (msgs.last['ts'] != _messages.last['ts'] || msgs.first['ts'] != _messages.first['ts']));
        if (changed || _unreachable || !_loaded) {
          final nearBottom = !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.offset < 120;
          final first = !_loaded;
          setState(() { _messages = msgs; _unreachable = false; _loaded = true; });
          if (changed && (nearBottom || first)) _scrollToBottom(animate: !first);
        }
      }
    } catch (_) {
    } finally {
      _msgPolling = false;
      if (!_disposed) _msgTimer = Timer(const Duration(seconds: 2), _pollMessages);
    }
  }

  Future<void> _pollInfo() async {
    if (_disposed || _infoPolling) return;
    _infoPolling = true;
    try {
      final info = await KnkApi.getGroupMembers(_owner, _g.groupId);
      if (_disposed) return;
      if (info != null && info['notFound'] == true) {
        setState(() => _membership = _Membership.groupGone);
      } else if (info != null) {
        final members = (info['members'] as List? ?? const [])
            .whereType<Map>()
            .map((m) {
              try { return GroupMember.fromJson(Map<String, dynamic>.from(m)); } catch (_) { return null; }
            })
            .whereType<GroupMember>()
            .toList();
        final muted = (info['muted'] as List? ?? const []).whereType<String>().toList();
        // Güncellemeden önce katılınmış gruplarda sahibin anahtarı ilk kez burada sabitlenir.
        if (_g.ownerPublicKey == null && info['ownerPublicKey'] is String) {
          _g.ownerPublicKey = info['ownerPublicKey'] as String;
          unawaited(LocalStore.updateGroup(_g));
        }
        var membership = _membership;
        if (_g.isOwner || members.any((m) => m.fipId == _me)) {
          membership = _Membership.member;
        } else {
          final reqs = await KnkApi.getGroupJoinRequests(_owner, _g.groupId);
          if (_disposed) return;
          if (reqs != null) {
            membership = reqs.any((r) => r['fromFipId'] == _me) ? _Membership.pending : _Membership.removed;
          }
        }
        List<Map<String, dynamic>>? joins;
        if (_g.isOwner) joins = await KnkApi.getGroupJoinRequests(_owner, _g.groupId);
        if (_disposed) return;
        setState(() {
          _g.members = members;
          _mutedMembers = muted;
          _membership = membership;
          if (joins != null) _pendingJoins = joins;
        });
        if (_g.isOwner) {
          await _distributeKeys();
        } else if (membership == _Membership.member) {
          await _fetchMyKey();
        }
      }
    } catch (_) {
    } finally {
      _infoPolling = false;
      if (!_disposed) _infoTimer = Timer(const Duration(seconds: 5), _pollInfo);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  // --- Actions ---

  Future<void> _send() async {
    if (_sending || _membership != _Membership.member) return;
    final raw = _msgCtrl.text;
    final error = validateMessage(raw);
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    final keyId = _g.currentKeyId;
    final key = _g.currentKey;
    if (keyId == null || key == null) {
      setState(() => _inputError = 'Grup şifreleme anahtarı henüz gelmedi. Grup sahibinin uygulamayı açması gerekiyor.');
      return;
    }
    final text = sanitizeMessage(raw);
    final ts = DateTime.now().millisecondsSinceEpoch;
    setState(() { _inputError = null; _sending = true; });
    final payload = await encryptGroupMessage(text, keyId, key);
    _decryptCache[payload] = text;
    final err = await KnkApi.sendGroupMessage(_owner, _g.groupId, _token,
      fromName: widget.displayName, text: payload, ts: ts,
    );
    if (_disposed) return;
    setState(() {
      _sending = false;
      if (err == null) {
        _msgCtrl.clear();
        _messages = [..._messages, {'from': _me, 'fromName': widget.displayName, 'text': payload, '_plain': text, '_enc': true, 'ts': ts}];
      } else {
        _inputError = err;
      }
    });
    if (err == null) _scrollToBottom();
  }

  Future<void> _acceptMember(Map<String, dynamic> req) async {
    final fipId = req['fromFipId'] as String?;
    if (fipId == null) return;
    final ok = await KnkApi.acceptGroupMember(_owner, _g.groupId, _token, fipId: fipId);
    if (_disposed) return;
    if (!ok) { _showToast('İşlem başarısız. Tekrar dene.'); return; }
    setState(() {
      _pendingJoins.removeWhere((r) => r['fromFipId'] == fipId);
      if (!_g.members.any((m) => m.fipId == fipId)) {
        _g.members = [..._g.members, GroupMember(fipId: fipId, name: req['fromName'] as String? ?? 'Bilinmeyen',
            serverUrl: req['fromServerUrl'] as String? ?? '', publicKey: req['fromPublicKey'] as String?)];
      }
    });
    // Yeni üyeye grup anahtarını hemen teslim et.
    await _distributeKeys();
  }

  Future<void> _rejectMember(Map<String, dynamic> req) async {
    final fipId = req['fromFipId'] as String?;
    if (fipId == null) return;
    final ok = await KnkApi.rejectGroupMember(_owner, _g.groupId, _token, fipId);
    if (_disposed) return;
    if (!ok) { _showToast('İşlem başarısız. Tekrar dene.'); return; }
    setState(() => _pendingJoins.removeWhere((r) => r['fromFipId'] == fipId));
  }

  Future<void> _muteMember(GroupMember member) async {
    final ok = await KnkApi.muteGroupMember(_owner, _g.groupId, _token, member.fipId);
    if (_disposed) return;
    if (!ok) { _showToast('İşlem başarısız. Tekrar dene.'); return; }
    setState(() { if (!_mutedMembers.contains(member.fipId)) _mutedMembers.add(member.fipId); });
    _showToast('${member.name} susturuldu.');
  }

  Future<void> _unmuteMember(GroupMember member) async {
    final ok = await KnkApi.unmuteGroupMember(_owner, _g.groupId, _token, member.fipId);
    if (_disposed) return;
    if (!ok) { _showToast('İşlem başarısız. Tekrar dene.'); return; }
    setState(() => _mutedMembers.remove(member.fipId));
    _showToast('${member.name} susturma kaldırıldı.');
  }

  Future<void> _kickMember(GroupMember member) async {
    final ok = await KnkApi.leaveGroup(_owner, _g.groupId, _token, member.fipId);
    if (_disposed) return;
    if (!ok) { _showToast('İşlem başarısız. Tekrar dene.'); return; }
    setState(() => _g.members = _g.members.where((m) => m.fipId != member.fipId).toList());
    _showToast('${member.name} gruptan atıldı.');
    // Atılan üye eski anahtarı biliyor: yeni mesajlar için anahtarı yenile ve kalanlara dağıt.
    await _rotateKey();
  }

  // --- Anahtar doğrulama ---

  Future<void> _loadVerified() async {
    final v = await LocalStore.loadVerifiedKeys();
    if (!_disposed) setState(() => _verifiedKeys = v);
  }

  /// Bir üyenin karşılaştırılacak anahtarı. Sahip için, katılırken sabitlenen
  /// anahtar kullanılır (sunucunun sonradan bildirdiği değil).
  String? _keyOf(GroupMember m) => (m.fipId == _g.ownerFipId && !_g.isOwner) ? _g.ownerPublicKey : m.publicKey;

  KeyTrust _trustOf(GroupMember m) => keyTrust(_verifiedKeys, m.fipId, _keyOf(m));

  String get _ownerName {
    for (final m in _g.members) {
      if (m.fipId == _g.ownerFipId) return m.name;
    }
    return 'Grup sahibi';
  }

  KeyTrust get _ownerTrust => keyTrust(_verifiedKeys, _g.ownerFipId, _g.ownerPublicKey);

  Future<void> _openVerify(String fipId, String name, String? publicKey) async {
    if (publicKey == null) {
      _showToast('Bu kişinin şifreleme anahtarı bilinmiyor.');
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VerifyKeyScreen(
      myFipId: _me, theirFipId: fipId, theirName: name, theirPublicKey: publicKey,
    )));
    await _loadVerified();
    // Doğrulama değiştiyse (ör. yeni anahtar onaylandı) bekleyen teslimleri tamamla.
    if (_g.isOwner && !_disposed) await _distributeKeys();
  }

  // --- Uçtan uca grup anahtarı ---

  /// Sahip: güncel anahtarı olmayan her üyeye anahtarı sarıp teslim eder.
  Future<void> _distributeKeys() async {
    if (!_g.isOwner) return;
    if (_g.currentKey == null) {
      // Şifreleme gelmeden önce oluşturulmuş grup: ilk anahtarı şimdi üret.
      await _rotateKey(distribute: false);
    }
    final keyId = _g.currentKeyId!;
    final key = _g.currentKey!;
    for (final m in _g.members.toList()) {
      final pub = m.publicKey;
      if (m.fipId == _me || pub == null || pub.isEmpty || m.keyId == keyId || _wrapping.contains(m.fipId)) continue;
      // Doğruladığımız anahtardan farklı bir anahtara grup anahtarını asla gönderme
      // (sunucu veya araya giren biri sahte anahtar sunuyor olabilir).
      if (keyTrust(_verifiedKeys, m.fipId, pub) == KeyTrust.changed) continue;
      _wrapping.add(m.fipId);
      try {
        final wrapped = await wrapGroupKey(groupId: _g.groupId, keyId: keyId, keyBase64: key, memberPublicKeyBase64: pub);
        await KnkApi.putGroupKey(_owner, _g.groupId, _token, m.fipId, encryptedKey: wrapped, keyId: keyId);
      } catch (_) {
        // Bir sonraki turda tekrar denenir (sunucu keyId'yi güncel göstermez).
      } finally {
        _wrapping.remove(m.fipId);
      }
      if (_disposed) return;
    }
  }

  /// Sahip: yeni bir grup anahtarı üretir; eski anahtarlar geçmiş mesajları okumak için tutulur.
  Future<void> _rotateKey({bool distribute = true}) async {
    final (keyId, key) = generateGroupKeyEntry();
    _g.keyring[keyId] = key;
    _g.currentKeyId = keyId;
    await LocalStore.updateGroup(_g);
    if (distribute && !_disposed) await _distributeKeys();
  }

  /// Üye: sahibin bize sardığı en güncel anahtarı alır ve anahtar halkasına ekler.
  Future<void> _fetchMyKey() async {
    final ownerPub = _g.ownerPublicKey;
    if (ownerPub == null) return;
    // Sahibin anahtarı doğrulanandan farklıysa ondan gelen anahtarı kabul etme.
    if (_ownerTrust == KeyTrust.changed) return;
    final res = await KnkApi.getMyGroupKey(_owner, _g.groupId, _token, _me);
    if (res == null || _disposed) return;
    final (wrapped, keyId) = res;
    if (_g.keyring.containsKey(keyId)) {
      if (_g.currentKeyId != keyId) {
        _g.currentKeyId = keyId;
        await LocalStore.updateGroup(_g);
      }
      return;
    }
    final entry = await unwrapGroupKey(groupId: _g.groupId, expectedKeyId: keyId, wrapped: wrapped, ownerPublicKeyBase64: ownerPub);
    if (entry == null || _disposed) return;
    _g.keyring[entry.$1] = entry.$2;
    _g.currentKeyId = entry.$1;
    await LocalStore.updateGroup(_g);
    if (_disposed) return;
    _keysChanged = true;
    setState(() {});
  }

  Future<void> _leaveOrDelete() async {
    final owner = _g.isOwner;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(owner ? 'Grubu sil' : 'Gruptan ayrıl'),
        content: Text(owner ? 'Grup ve tüm mesajları herkes için silinecek.' : '${_g.name} grubundan ayrılacaksın.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(style: knkDangerButtonStyle(), onPressed: () => Navigator.pop(ctx, true), child: Text(owner ? 'Grubu sil' : 'Ayrıl')),
        ],
      ),
    );
    if (confirm != true || _disposed) return;
    // Grup sunucuda zaten yoksa yalnızca yerelden kaldır.
    final ok = _membership == _Membership.groupGone || _membership == _Membership.legacy ||
        (owner ? await KnkApi.deleteGroup(_owner, _g.groupId, _token) : await KnkApi.leaveGroup(_owner, _g.groupId, _token, _me));
    if (_disposed || !mounted) return;
    if (!ok) { _showToast('Sunucuya ulaşılamadı. Tekrar dene.'); return; }
    Navigator.pop(context, true);
  }

  String? _toastMsg;
  Timer? _toastTimer;
  void _showToast(String msg) {
    if (_disposed) return;
    _toastTimer?.cancel();
    setState(() => _toastMsg = msg);
    _toastTimer = Timer(const Duration(seconds: 3), () { if (!_disposed) setState(() => _toastMsg = null); });
  }

  // --- Sheets ---

  void _showJoinRequests() {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => ListView(padding: const EdgeInsets.fromLTRB(Space.s3, 0, Space.s3, Space.s3), children: [
          const Text('Katılma istekleri', style: KnkText.h2),
          const SizedBox(height: Space.s2),
          if (_pendingJoins.isEmpty) const Text('Bekleyen istek yok.', style: KnkText.small),
          ..._pendingJoins.map((req) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(req['fromName'] as String? ?? 'Bilinmeyen', style: KnkText.strong),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Kabul et', icon: const Icon(Icons.check, color: KnkColors.accent),
                  onPressed: () async { await _acceptMember(req); if (ctx.mounted) set(() {}); }),
              IconButton(tooltip: 'Reddet', icon: const Icon(Icons.close, color: KnkColors.danger),
                  onPressed: () async { await _rejectMember(req); if (ctx.mounted) set(() {}); }),
            ]),
          )),
        ]),
      ),
    );
  }

  void _showMemberMenu(GroupMember member) {
    final isMuted = _mutedMembers.contains(member.fipId);
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isMuted ? Icons.volume_up_outlined : Icons.volume_off_outlined, color: KnkColors.accent),
              title: Text(isMuted ? '${member.name} susturmayı kaldır' : '${member.name} kullanıcısını sustur'),
              onTap: () {
                Navigator.pop(sheetCtx);
                isMuted ? _unmuteMember(member) : _muteMember(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: KnkColors.danger),
              title: Text('${member.name} kullanıcısını gruptan at', style: const TextStyle(color: KnkColors.danger)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _kickMember(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Vazgeç'),
              onTap: () => Navigator.pop(sheetCtx),
            ),
            const SizedBox(height: Space.s1),
          ],
        ),
      ),
    );
  }

  void _showInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(controller: controller, padding: const EdgeInsets.fromLTRB(Space.s3, 0, Space.s3, Space.s3), children: [
          Text(_g.name, style: KnkText.h2),
          const SizedBox(height: Space.s3),
          const SectionLabel('Grup adresi'),
          Row(children: [
            Expanded(child: SelectableText(_g.address, style: KnkText.small.copyWith(color: KnkColors.accent))),
            IconButton(
              tooltip: 'Kopyala',
              icon: const Icon(Icons.content_copy_outlined, color: KnkColors.textDim, size: 16),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _g.address));
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                _showToast('Grup adresi kopyalandı.');
              },
            ),
          ]),
          const SizedBox(height: Space.s3),
          SectionLabel('Üyeler · ${_g.members.length}'),
          ..._g.members.map((m) {
            final isMuted = _mutedMembers.contains(m.fipId);
            final isOwner = m.fipId == _g.ownerFipId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(children: [
                Flexible(child: Text(m.fipId == _me ? '${m.name} (sen)' : m.name, overflow: TextOverflow.ellipsis, style: KnkText.strong)),
                if (isOwner) const SizedBox(width: Space.s1),
                if (isOwner) const Text('kurucu', style: TextStyle(color: KnkColors.accent2, fontSize: 13)),
                if (isMuted) const SizedBox(width: Space.s1),
                if (isMuted) const Icon(Icons.volume_off_outlined, color: KnkColors.textDim, size: 16),
              ]),
              subtitle: switch (_trustOf(m)) {
                KeyTrust.verified when m.fipId != _me =>
                  const Text('doğrulandı', style: TextStyle(color: KnkColors.accent, fontSize: 13)),
                KeyTrust.changed when m.fipId != _me =>
                  const Text('anahtar değişti, grup anahtarı gönderilmiyor', style: TextStyle(color: KnkColors.danger, fontSize: 13)),
                _ => null,
              },
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (m.fipId != _me)
                  IconButton(
                    tooltip: 'Güvenlik numarası',
                    icon: Icon(
                      switch (_trustOf(m)) {
                        KeyTrust.verified => Icons.verified_user_outlined,
                        KeyTrust.changed => Icons.gpp_bad_outlined,
                        _ => Icons.gpp_maybe_outlined,
                      },
                      size: 18,
                      color: switch (_trustOf(m)) {
                        KeyTrust.verified => KnkColors.accent,
                        KeyTrust.changed => KnkColors.danger,
                        _ => KnkColors.textDim,
                      },
                    ),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _openVerify(m.fipId, m.name, _keyOf(m));
                    },
                  ),
                if (_g.isOwner && !isOwner)
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: KnkColors.textDim, size: 18),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _showMemberMenu(m);
                    },
                  ),
              ]),
            );
          }),
          const SizedBox(height: Space.s3),
          OutlinedButton.icon(
            style: knkGhostButtonStyle().copyWith(
              foregroundColor: WidgetStateProperty.all(KnkColors.danger),
              side: WidgetStateProperty.resolveWith((s) => BorderSide(color: KnkColors.danger.withOpacity(s.contains(WidgetState.hovered) ? 1 : 0.4))),
              backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? KnkColors.danger.withOpacity(0.08) : Colors.transparent),
            ),
            icon: Icon(_g.isOwner ? Icons.delete_outline : Icons.logout, size: 18),
            label: Text(_g.isOwner ? 'Grubu sil' : 'Gruptan ayrıl'),
            onPressed: () {
              Navigator.pop(sheetCtx);
              _leaveOrDelete();
            },
          ),
        ]),
      ),
    );
  }

  String _formatTime(num ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget? _statusBanner() {
    String? text;
    var tone = KnkColors.accent2;
    var icon = Icons.info_outline;
    switch (_membership) {
      case _Membership.pending:
        text = 'Katılma isteğin grup kurucusunun onayını bekliyor.';
        icon = Icons.schedule;
      case _Membership.removed:
        text = 'Bu grubun üyesi değilsin. İsteğin reddedilmiş ya da gruptan çıkarılmış olabilirsin.';
        icon = Icons.person_off_outlined;
        tone = KnkColors.danger;
      case _Membership.groupGone:
        text = 'Bu grup artık yok. Silinmiş ya da sunucusu sıfırlanmış olabilir.';
        icon = Icons.cloud_off_outlined;
        tone = KnkColors.danger;
      case _Membership.legacy:
        text = 'Bu grup uygulamanın eski bir sürümüyle eklendi. Grubu listeden kaldırıp yeniden oluştur ya da katıl.';
      case _Membership.member:
        if (_mutedMembers.contains(_me)) {
          text = 'Grup kurucusu seni susturdu.';
          icon = Icons.volume_off_outlined;
        } else if (!_g.isOwner && _ownerTrust == KeyTrust.changed) {
          text = 'Grup kurucusunun anahtarı doğruladığın anahtardan farklı. Güvenlik numarasını yeniden karşılaştırana kadar mesaj gönderemezsin.';
          icon = Icons.gpp_bad_outlined;
          tone = KnkColors.danger;
        } else if (_g.currentKey == null) {
          text = 'Şifreleme anahtarı bekleniyor. Grup kurucusu uygulamayı açınca mesajlaşabilirsin.';
          icon = Icons.key_outlined;
        }
      case _Membership.loading:
        break;
    }
    if (text == null && _unreachable) {
      text = 'Grup sunucusuna ulaşılamıyor. Yeniden bağlanılıyor…';
      icon = Icons.cloud_off_outlined;
    }
    if (text == null) return null;
    return NoticeBar(icon: icon, text: text, tone: tone);
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _membership == _Membership.member && !_mutedMembers.contains(_me) && _g.currentKey != null &&
        (_g.isOwner || _ownerTrust != KeyTrust.changed);
    final banner = _statusBanner();
    final ownerTone = switch (_ownerTrust) {
      KeyTrust.verified => KnkColors.accent,
      KeyTrust.changed => KnkColors.danger,
      _ => KnkColors.accent2,
    };
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_g.name, overflow: TextOverflow.ellipsis),
          Text('${_g.members.isEmpty ? '' : '${_g.members.length} üye · '}kod ${_g.groupCode}', style: KnkText.meta.merge(KnkText.tabular)),
        ]),
        actions: [
          if (_g.isOwner)
            Badge(
              isLabelVisible: _pendingJoins.isNotEmpty,
              label: Text('${_pendingJoins.length}'),
              backgroundColor: KnkColors.accent2,
              textColor: KnkColors.onAccent,
              offset: const Offset(-4, 4),
              child: IconButton(
                tooltip: 'Katılma istekleri',
                icon: const Icon(Icons.person_add_alt_outlined),
                onPressed: _showJoinRequests,
              ),
            ),
          IconButton(tooltip: 'Grup bilgisi', icon: const Icon(Icons.info_outline), onPressed: _showInfo),
          const SizedBox(width: Space.s1),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_g.currentKey != null && _membership == _Membership.member)
                Material(
                  color: KnkColors.accentWash,
                  child: InkWell(
                    onTap: _g.isOwner ? null : () => _openVerify(_g.ownerFipId, _ownerName, _g.ownerPublicKey),
                    child: ContentWidth(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
                      child: Row(children: [
                        const Icon(Icons.lock_outline, color: KnkColors.accent, size: 16),
                        const SizedBox(width: Space.s1),
                        const Text('uçtan uca şifreli', style: TextStyle(color: KnkColors.accent, fontSize: 13)),
                        const Spacer(),
                        if (!_g.isOwner)
                          Text(
                            switch (_ownerTrust) {
                              KeyTrust.verified => 'kurucu doğrulandı',
                              KeyTrust.changed => 'kurucunun anahtarı değişti',
                              _ => 'kurucuyu doğrula',
                            },
                            style: TextStyle(color: ownerTone, fontSize: 13,
                                decoration: _ownerTrust == KeyTrust.verified ? null : TextDecoration.underline, decorationColor: ownerTone),
                          ),
                      ]),
                    )),
                  ),
                ),
              if (banner != null) banner,
              Expanded(
                child: !_loaded && _messages.isEmpty && !_unreachable && _membership != _Membership.groupGone
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _messages.isEmpty
                        ? const CenterNote(icon: Icons.forum_outlined, title: 'Henüz mesaj yok.', body: 'Gruptaki ilk mesajı sen yaz.')
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(vertical: Space.s2),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) => ContentWidth(child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                              child: _buildBubble(_messages[i]),
                            )),
                          ),
              ),
              if (_inputError != null) NoticeBar(icon: Icons.error_outline, text: _inputError!, tone: KnkColors.danger),
              MessageComposer(
                controller: _msgCtrl,
                enabled: canSend,
                sending: _sending,
                hint: canSend ? 'Gruba yaz' : 'Şu an mesaj gönderemezsin',
                onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
                onSend: _send,
              ),
            ],
          ),
          if (_toastMsg != null)
            Positioned(
              left: Space.s2, right: Space.s2, bottom: Space.s7,
              child: ContentWidth(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
                decoration: BoxDecoration(color: KnkColors.panelAlt, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(KnkRadius.card), boxShadow: knkShadow()),
                child: Text(_toastMsg!, textAlign: TextAlign.center, style: KnkText.small.copyWith(color: KnkColors.text)),
              )),
            ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> m) {
    final isMe = m['from'] == _me;
    final plain = m['_plain'] as String?;
    final undecryptable = plain == null;
    // Şifreleme öncesinden kalan (veya sunucuya doğrudan yazılmış) düz metin doğrulanamaz.
    final unverified = !undecryptable && m['_enc'] != true;
    final fg = isMe ? KnkColors.onAccent : KnkColors.text;
    final maxW = (MediaQuery.sizeOf(context).width * 0.78).clamp(0.0, 520.0);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.s1),
        padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s2, Space.s1),
        constraints: BoxConstraints(maxWidth: maxW),
        decoration: BoxDecoration(
          color: isMe ? KnkColors.accent : KnkColors.panel,
          border: isMe ? null : Border.all(color: KnkColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(KnkRadius.bubble), topRight: const Radius.circular(KnkRadius.bubble),
            bottomLeft: Radius.circular(isMe ? KnkRadius.bubble : 2), bottomRight: Radius.circular(isMe ? 2 : KnkRadius.bubble),
          ),
        ),
        child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          if (!isMe) Text(m['fromName'] as String? ?? '', style: const TextStyle(color: KnkColors.accent2, fontSize: 13, fontWeight: FontWeight.w600)),
          if (undecryptable)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 16, color: fg.withOpacity(0.7)),
              const SizedBox(width: Space.s1),
              Flexible(child: Text('Bu şifreli mesaj çözülemedi.', style: TextStyle(color: fg.withOpacity(0.7), fontSize: 15, fontStyle: FontStyle.italic))),
            ])
          else
            Text(filterProfanity(plain), style: TextStyle(color: fg, fontSize: 15, height: 1.45)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (unverified) ...[
              const Tooltip(
                message: 'Bu mesaj şifresiz; kimden geldiği doğrulanamıyor.',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_amber_outlined, size: 14, color: KnkColors.accent2),
                  SizedBox(width: Space.s1),
                  Text('şifresiz', style: TextStyle(color: KnkColors.accent2, fontSize: 11)),
                ]),
              ),
              const SizedBox(width: Space.s1),
            ],
            Text(_formatTime(m['ts'] as num), style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11).merge(KnkText.tabular)),
          ]),
        ]),
      ),
    );
  }
}
