import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';

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
        msgs.removeWhere((m) => m['ts'] is! num || m['from'] is! String);
        msgs.sort((a, b) => (a['ts'] as num).compareTo(b['ts'] as num));
        final changed = msgs.length != _messages.length ||
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
    final text = sanitizeMessage(raw);
    final ts = DateTime.now().millisecondsSinceEpoch;
    setState(() { _inputError = null; _sending = true; });
    final err = await KnkApi.sendGroupMessage(_owner, _g.groupId, _token,
      fromName: widget.displayName, text: text, ts: ts,
    );
    if (_disposed) return;
    setState(() {
      _sending = false;
      if (err == null) {
        _msgCtrl.clear();
        _messages = [..._messages, {'from': _me, 'fromName': widget.displayName, 'text': text, 'ts': ts}];
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
        _g.members = [..._g.members, GroupMember(fipId: fipId, name: req['fromName'] as String? ?? 'Bilinmeyen', serverUrl: req['fromServerUrl'] as String? ?? '')];
      }
    });
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
  }

  Future<void> _leaveOrDelete() async {
    final owner = _g.isOwner;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: Text(owner ? 'Grubu sil' : 'Gruptan ayrıl', style: const TextStyle(color: KnkColors.text, fontSize: 15)),
        content: Text(
          owner ? 'Grup ve tüm mesajları herkes için silinecek.' : '${_g.name} grubundan ayrılacaksın.',
          style: const TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç', style: TextStyle(color: KnkColors.textDim))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(owner ? 'Sil' : 'Ayrıl', style: const TextStyle(color: KnkColors.danger))),
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
      context: context, backgroundColor: KnkColors.panel,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Katılma İstekleri', style: TextStyle(color: KnkColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          if (_pendingJoins.isEmpty) const Text('Bekleyen istek yok.', style: TextStyle(color: KnkColors.textDim, fontSize: 13)),
          ..._pendingJoins.map((req) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(req['fromName'] as String? ?? 'Bilinmeyen', style: const TextStyle(color: KnkColors.text, fontSize: 14)),
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
      backgroundColor: KnkColors.panel,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off, color: KnkColors.accent),
              title: Text(isMuted ? '${member.name} susturmayı kaldır' : '${member.name} kullanıcısını sustur',
                  style: const TextStyle(color: KnkColors.text)),
              onTap: () {
                Navigator.pop(sheetCtx);
                isMuted ? _unmuteMember(member) : _muteMember(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: KnkColors.danger),
              title: Text('${member.name} kullanıcısını gruptan at', style: const TextStyle(color: KnkColors.danger)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _kickMember(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: KnkColors.textDim),
              title: const Text('Vazgeç', style: TextStyle(color: KnkColors.textDim)),
              onTap: () => Navigator.pop(sheetCtx),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo() {
    showModalBottomSheet(
      context: context, backgroundColor: KnkColors.panel,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(controller: controller, padding: const EdgeInsets.all(20), children: [
          Text(_g.name, style: const TextStyle(color: KnkColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          const Text('GRUP ADRESİ', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: SelectableText(_g.address, style: const TextStyle(color: KnkColors.accent, fontSize: 12, fontFamily: 'monospace'))),
            IconButton(
              tooltip: 'Kopyala',
              icon: const Icon(Icons.copy, color: KnkColors.textDim, size: 16),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _g.address));
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                _showToast('Grup adresi kopyalandı.');
              },
            ),
          ]),
          const SizedBox(height: 16),
          Text('ÜYELER · ${_g.members.length}', style: const TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          ..._g.members.map((m) {
            final isMuted = _mutedMembers.contains(m.fipId);
            final isOwner = m.fipId == _g.ownerFipId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(children: [
                Flexible(child: Text(m.fipId == _me ? '${m.name} (sen)' : m.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: KnkColors.text, fontSize: 13))),
                if (isOwner) const SizedBox(width: 6),
                if (isOwner) const Text('(sahip)', style: TextStyle(color: KnkColors.textDim, fontSize: 10)),
                if (isMuted) const SizedBox(width: 6),
                if (isMuted) const Icon(Icons.volume_off, color: KnkColors.textDim, size: 13),
              ]),
              trailing: _g.isOwner && !isOwner
                  ? IconButton(
                      icon: const Icon(Icons.more_vert, color: KnkColors.textDim, size: 18),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _showMemberMenu(m);
                      },
                    )
                  : null,
            );
          }),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: KnkColors.danger, side: BorderSide(color: KnkColors.danger.withOpacity(0.4))),
            icon: Icon(_g.isOwner ? Icons.delete_outline : Icons.logout, size: 16),
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
    switch (_membership) {
      case _Membership.pending:
        text = 'Katılma isteğin grup sahibinin onayını bekliyor.';
      case _Membership.removed:
        text = 'Bu grubun üyesi değilsin (istek reddedildi veya gruptan çıkarıldın).';
      case _Membership.groupGone:
        text = 'Bu grup artık mevcut değil (silinmiş veya sunucu sıfırlanmış).';
      case _Membership.legacy:
        text = 'Bu grup uygulamanın eski bir sürümüyle eklendi. Grubu listeden kaldırıp yeniden oluştur veya katıl.';
      case _Membership.member:
        if (_mutedMembers.contains(_me)) text = 'Grup yöneticisi seni susturdu.';
      case _Membership.loading:
        break;
    }
    if (text == null && _unreachable) text = 'Grup sunucusuna ulaşılamıyor. Yeniden bağlanılıyor…';
    if (text == null) return null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: KnkColors.accent2.withOpacity(0.12),
      child: Text(text, style: const TextStyle(color: KnkColors.accent2, fontSize: 11.5, height: 1.4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _membership == _Membership.member && !_mutedMembers.contains(_me);
    final banner = _statusBanner();
    return Scaffold(
      appBar: AppBar(
        title: Text(_g.name),
        actions: [
          if (_g.isOwner)
            Stack(children: [
              IconButton(
                tooltip: 'Katılma istekleri',
                icon: Icon(Icons.person_add, color: _pendingJoins.isNotEmpty ? KnkColors.text : KnkColors.textDim),
                onPressed: _showJoinRequests,
              ),
              if (_pendingJoins.isNotEmpty)
                Positioned(top: 8, right: 8, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: KnkColors.accent2, shape: BoxShape.circle))),
            ]),
          IconButton(tooltip: 'Grup bilgisi', icon: const Icon(Icons.info_outline, color: KnkColors.text), onPressed: _showInfo),
        ],
      ),
      backgroundColor: KnkColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              if (banner != null) banner,
              Expanded(
                child: !_loaded && _messages.isEmpty && !_unreachable && _membership != _Membership.groupGone
                    ? const Center(child: CircularProgressIndicator(color: KnkColors.accent, strokeWidth: 2))
                    : _messages.isEmpty
                        ? const Center(child: Text('Henüz mesaj yok.', style: TextStyle(color: KnkColors.textDim, fontSize: 12)))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) => _buildBubble(_messages[i]),
                          ),
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
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: KnkColors.line))),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _msgCtrl,
                        enabled: canSend,
                        style: const TextStyle(color: KnkColors.text, fontSize: 14),
                        maxLength: maxMessageLength,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: canSend ? 'Mesaj yaz…' : 'Mesaj gönderemezsin',
                          hintStyle: const TextStyle(color: KnkColors.textDim, fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(20)),
                          disabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(20)),
                          focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(20)),
                        ),
                        minLines: 1, maxLines: 4,
                        onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
                        // Enter ile gönderdikten sonra odak kutuda kalsın; art arda mesaj yazılabilsin.
                        onEditingComplete: () {},
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: (canSend && !_sending) ? _send : null,
                      borderRadius: BorderRadius.circular(21),
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: canSend ? KnkColors.accent : KnkColors.line, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: _sending
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06251A)))
                            : Icon(Icons.send, color: canSend ? const Color(0xFF06251A) : KnkColors.textDim, size: 18),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
          if (_toastMsg != null)
            Positioned(
              left: 16, right: 16, bottom: 84,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: KnkColors.panelAlt, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
                child: Text(_toastMsg!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: KnkColors.text)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> m) {
    final isMe = m['from'] == _me;
    final displayText = filterProfanity(m['text'] as String? ?? '');
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? KnkColors.accent.withOpacity(0.18) : KnkColors.panel,
          border: Border.all(color: isMe ? KnkColors.accent.withOpacity(0.3) : KnkColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          if (!isMe) Text(m['fromName'] as String? ?? '', style: const TextStyle(color: KnkColors.accent, fontSize: 10, fontWeight: FontWeight.w600)),
          Text(displayText, style: const TextStyle(color: KnkColors.text, fontSize: 14)),
          const SizedBox(height: 2),
          Text(_formatTime(m['ts'] as num), style: const TextStyle(color: KnkColors.textDim, fontSize: 9.5)),
        ]),
      ),
    );
  }
}
