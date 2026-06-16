import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';

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
  Timer? _joinTimer;
  Timer? _muteTimer;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _pollMessages();
    if (widget.group.isOwner) {
      _pollJoinRequests();
      _pollMutedMembers();
    }
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    _joinTimer?.cancel();
    _muteTimer?.cancel();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _pollMessages() {
    _msgTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final msgs = await KnkApi.getGroupMessages(widget.myServerUrl, widget.group.groupId);
      msgs.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
      if (mounted) setState(() => _messages = msgs);
    });
  }

  void _pollJoinRequests() {
    _joinTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final reqs = await KnkApi.getGroupJoinRequests(widget.myServerUrl, widget.group.groupId);
      if (mounted) setState(() => _pendingJoins = reqs);
    });
  }

  void _pollMutedMembers() {
    _muteTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final muted = await KnkApi.getMutedMembers(widget.myServerUrl, widget.group.groupId);
      if (mounted) setState(() => _mutedMembers = muted);
    });
    // İlk yükleme
    KnkApi.getMutedMembers(widget.myServerUrl, widget.group.groupId).then((muted) {
      if (mounted) setState(() => _mutedMembers = muted);
    });
  }

  Future<void> _send() async {
    final raw = _msgCtrl.text;
    final error = validateMessage(raw);
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    final text = sanitizeMessage(raw);
    setState(() => _inputError = null);
    _msgCtrl.clear();
    final memberUrls = widget.group.members.map((m) => m.serverUrl).toList();
    memberUrls.add(widget.myServerUrl);
    await KnkApi.sendGroupMessage(memberUrls, widget.group.groupId,
      from: widget.identity.fipId, fromName: widget.displayName,
      text: text, ts: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _acceptMember(Map<String, dynamic> req) async {
    await KnkApi.acceptGroupMember(widget.myServerUrl, widget.group.groupId,
      fipId: req['fromFipId'] as String,
      name: req['fromName'] as String? ?? 'Bilinmeyen',
      serverUrl: req['fromServerUrl'] as String? ?? '',
    );
    setState(() => _pendingJoins.remove(req));
  }

  Future<void> _rejectMember(Map<String, dynamic> req) async {
    await KnkApi.rejectGroupMember(widget.myServerUrl, widget.group.groupId, req['fromFipId'] as String);
    setState(() => _pendingJoins.remove(req));
  }

  Future<void> _muteMember(GroupMember member) async {
    await KnkApi.muteGroupMember(widget.group.ownerServerUrl, widget.group.groupId, member.fipId);
    if (mounted) setState(() { if (!_mutedMembers.contains(member.fipId)) _mutedMembers.add(member.fipId); });
    if (mounted) _showToast('${member.name} susturuldu.');
  }

  Future<void> _unmuteMember(GroupMember member) async {
    await KnkApi.unmuteGroupMember(widget.group.ownerServerUrl, widget.group.groupId, member.fipId);
    if (mounted) setState(() => _mutedMembers.remove(member.fipId));
    if (mounted) _showToast('${member.name} susturma kaldırıldı.');
  }

  Future<void> _kickMember(GroupMember member) async {
    await KnkApi.leaveGroup(widget.group.ownerServerUrl, widget.group.groupId, member.fipId);
    if (mounted) setState(() => widget.group.members.removeWhere((m) => m.fipId == member.fipId));
    if (mounted) _showToast('${member.name} gruptan atıldı.');
  }

  String? _toastMsg;
  void _showToast(String msg) {
    setState(() => _toastMsg = msg);
    Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _toastMsg = null); });
  }

  void _showJoinRequests() {
    showModalBottomSheet(
      context: context, backgroundColor: KnkColors.panel,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Katılma İstekleri', style: TextStyle(color: KnkColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          if (_pendingJoins.isEmpty) const Text('Bekleyen istek yok.', style: TextStyle(color: KnkColors.textDim, fontSize: 13)),
          ..._pendingJoins.map((req) => ListTile(
            title: Text(req['fromName'] as String? ?? 'Bilinmeyen', style: const TextStyle(color: KnkColors.text, fontSize: 14)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.check, color: KnkColors.accent), onPressed: () { _acceptMember(req); set(() {}); }),
              IconButton(icon: const Icon(Icons.close, color: KnkColors.danger), onPressed: () { _rejectMember(req); set(() {}); }),
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
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off, color: KnkColors.accent),
              title: Text(isMuted ? '${member.name} susturmayı kaldır' : '${member.name} kullanıcısını sustur',
                  style: const TextStyle(color: KnkColors.text)),
              onTap: () {
                Navigator.pop(context);
                if (isMuted) {
                  _unmuteMember(member);
                } else {
                  _muteMember(member);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: KnkColors.danger),
              title: Text('${member.name} kullanıcısını gruptan at', style: const TextStyle(color: KnkColors.danger)),
              onTap: () {
                Navigator.pop(context);
                _kickMember(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: KnkColors.textDim),
              title: const Text('Vazgeç', style: TextStyle(color: KnkColors.textDim)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo() {
    showModalBottomSheet(
      context: context, backgroundColor: KnkColors.panel,
      builder: (_) => ListView(padding: const EdgeInsets.all(20), children: [
        Text(widget.group.name, style: const TextStyle(color: KnkColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        if (widget.group.isOwner) ...[
          const Text('GRUP ADRESİ', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: widget.group.address)),
            child: Text(widget.group.address, style: const TextStyle(color: KnkColors.accent, fontSize: 12, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 16),
        ],
        const Text('ÜYELER', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        ...widget.group.members.map((m) {
          final isMuted = _mutedMembers.contains(m.fipId);
          final isOwner = m.fipId == widget.group.ownerFipId;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(children: [
              Text(m.name, style: const TextStyle(color: KnkColors.text, fontSize: 13)),
              if (isOwner) const SizedBox(width: 6),
              if (isOwner) const Text('(sahip)', style: TextStyle(color: KnkColors.textDim, fontSize: 10)),
              if (isMuted) const SizedBox(width: 6),
              if (isMuted) const Icon(Icons.volume_off, color: KnkColors.textDim, size: 13),
            ]),
            trailing: widget.group.isOwner && !isOwner
                ? IconButton(
                    icon: const Icon(Icons.more_vert, color: KnkColors.textDim, size: 18),
                    onPressed: () {
                      Navigator.pop(context);
                      _showMemberMenu(m);
                    },
                  )
                : null,
          );
        }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myFipId = widget.identity.fipId;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          if (widget.group.isOwner && _pendingJoins.isNotEmpty)
            Stack(children: [
              IconButton(icon: const Icon(Icons.person_add, color: KnkColors.text), onPressed: _showJoinRequests),
              Positioned(top: 8, right: 8, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: KnkColors.accent2, shape: BoxShape.circle))),
            ])
          else if (widget.group.isOwner)
            IconButton(icon: const Icon(Icons.person_add, color: KnkColors.textDim), onPressed: _showJoinRequests),
          IconButton(icon: const Icon(Icons.info_outline, color: KnkColors.text), onPressed: _showInfo),
        ],
      ),
      backgroundColor: KnkColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final isMe = m['from'] == myFipId;
                    final displayText = filterProfanity(m['text'] as String? ?? '');
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe ? KnkColors.accent.withOpacity(0.18) : KnkColors.panel,
                          border: Border.all(color: isMe ? KnkColors.accent.withOpacity(0.3) : KnkColors.line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                          if (!isMe) Text(m['fromName'] as String? ?? '', style: const TextStyle(color: KnkColors.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                          Text(displayText, style: const TextStyle(color: KnkColors.text, fontSize: 14)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              if (_inputError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: KnkColors.danger.withOpacity(0.1),
                  child: Text(_inputError!, style: const TextStyle(color: KnkColors.danger, fontSize: 12)),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: KnkColors.line))),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      style: const TextStyle(color: KnkColors.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Mesaj yaz…',
                        hintStyle: const TextStyle(color: KnkColors.textDim, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(20)),
                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(20)),
                      ),
                      minLines: 1, maxLines: 4,
                      onChanged: (_) { if (_inputError != null) setState(() => _inputError = null); },
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 42, height: 42,
                      decoration: const BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle),
                      child: const Icon(Icons.send, color: Color(0xFF06251A), size: 18),
                    ),
                  ),
                ]),
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
}
