import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../fip.dart';
import '../local_store.dart';
import '../photon_api.dart';
import '../theme.dart';
import '../profanity_filter.dart';
import '../message_guard.dart';
import '../offline_queue.dart';
import '../chat_wallpaper.dart';
import '../translate_service.dart';

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
  List<Map<String, dynamic>> _announcements = [];
  Timer? _msgTimer;
  Timer? _joinTimer;
  Timer? _muteTimer;
  Timer? _annTimer;
  String? _inputError;
  bool _annExpanded = false;
  final Map<String, String> _translations = {};
  final Map<String, String> _filtered = {};
  final Set<String> _translating = {};

  @override
  void initState() {
    super.initState();
    _pollMessages();
    _pollAnnouncements();
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
    _annTimer?.cancel();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
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

  void _onLongPressGroupMessage(Map<String, dynamic> m) {
    final msgId = m['msgId'] as String? ?? '';
    final text = m['text'] as String? ?? '';
    if (text.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: PhotonColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(Icons.translate, color: PhotonColors.accent),
          title: Text('Çevir', style: TextStyle(color: PhotonColors.text)),
          onTap: () {
            Navigator.pop(context);
            _translateMessage(msgId, text);
          },
        ),
      ])),
    );
  }

  void _pollMessages() {
    _msgTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await OfflineQueue.instance.flush();
      if (mounted) setState(() {});
      final msgs = await PhotonApi.getGroupMessages(widget.myServerUrl, widget.group.groupId);
      msgs.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
      if (mounted) setState(() => _messages = msgs);
    });
  }

  void _pollJoinRequests() {
    _joinTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final reqs = await PhotonApi.getGroupJoinRequests(widget.myServerUrl, widget.group.groupId);
      if (mounted) setState(() => _pendingJoins = reqs);
    });
  }

  void _pollMutedMembers() {
    _muteTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final muted = await PhotonApi.getMutedMembers(widget.myServerUrl, widget.group.groupId);
      if (mounted) setState(() => _mutedMembers = muted);
    });
    PhotonApi.getMutedMembers(widget.myServerUrl, widget.group.groupId).then((muted) {
      if (mounted) setState(() => _mutedMembers = muted);
    });
  }

  void _pollAnnouncements() {
    _annTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final anns = await PhotonApi.getGroupAnnouncements(widget.myServerUrl, widget.group.groupId);
      if (mounted) setState(() => _announcements = anns);
    });
    PhotonApi.getGroupAnnouncements(widget.myServerUrl, widget.group.groupId).then((a) {
      if (mounted) setState(() => _announcements = a);
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
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      await PhotonApi.sendGroupMessage(memberUrls, widget.group.groupId,
        from: widget.identity.fipId, fromName: widget.displayName,
        text: text, ts: ts,
      );
    } on SocketException {
      await OfflineQueue.instance.enqueue(QueuedMessage(
        chatKey: widget.group.groupId, receiverServerUrl: widget.myServerUrl,
        from: widget.identity.fipId, text: text, ts: ts,
        isGroup: true, groupMemberUrls: memberUrls,
        groupId: widget.group.groupId, fromName: widget.displayName,
      ));
      if (mounted) setState(() {});
    } on TimeoutException {
      await OfflineQueue.instance.enqueue(QueuedMessage(
        chatKey: widget.group.groupId, receiverServerUrl: widget.myServerUrl,
        from: widget.identity.fipId, text: text, ts: ts,
        isGroup: true, groupMemberUrls: memberUrls,
        groupId: widget.group.groupId, fromName: widget.displayName,
      ));
      if (mounted) setState(() {});
    }
  }

  Future<void> _vote(Map<String, dynamic> pollMsg, int optionIndex) async {
    final msgIdVal = pollMsg['msgId'] as String? ?? '';
    await PhotonApi.voteOnPoll(widget.myServerUrl, widget.group.groupId, msgIdVal, widget.identity.fipId, optionIndex);
    setState(() {
      if (pollMsg['votes'] == null) pollMsg['votes'] = {};
      (pollMsg['votes'] as Map)[widget.identity.fipId] = optionIndex;
    });
  }

  Future<void> _acceptMember(Map<String, dynamic> req) async {
    await PhotonApi.acceptGroupMember(widget.myServerUrl, widget.group.groupId,
      fipId: req['fromFipId'] as String,
      name: req['fromName'] as String? ?? 'Bilinmeyen',
      serverUrl: req['fromServerUrl'] as String? ?? '',
    );
    setState(() => _pendingJoins.remove(req));
  }

  Future<void> _rejectMember(Map<String, dynamic> req) async {
    await PhotonApi.rejectGroupMember(widget.myServerUrl, widget.group.groupId, req['fromFipId'] as String);
    setState(() => _pendingJoins.remove(req));
  }

  Future<void> _muteMember(GroupMember member) async {
    await PhotonApi.muteGroupMember(widget.group.ownerServerUrl, widget.group.groupId, member.fipId);
    await PhotonApi.sendNotification(member.serverUrl, member.fipId,
        'Susturuldunuz', '"${widget.group.name}" grubunda susturuldunuz');
    if (mounted) setState(() { if (!_mutedMembers.contains(member.fipId)) _mutedMembers.add(member.fipId); });
    if (mounted) _showToast('${member.name} susturuldu.');
  }

  Future<void> _unmuteMember(GroupMember member) async {
    await PhotonApi.unmuteGroupMember(widget.group.ownerServerUrl, widget.group.groupId, member.fipId);
    if (mounted) setState(() => _mutedMembers.remove(member.fipId));
    if (mounted) _showToast('${member.name} susturma kaldırıldı.');
  }

  Future<void> _kickMember(GroupMember member) async {
    await PhotonApi.leaveGroup(widget.group.ownerServerUrl, widget.group.groupId, member.fipId);
    await PhotonApi.sendNotification(member.serverUrl, member.fipId,
        'Gruptan çıkarıldınız', '"${widget.group.name}" grubundan çıkarıldınız');
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
      context: context, backgroundColor: PhotonColors.panel,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => ListView(padding: const EdgeInsets.all(20), children: [
          Text('Katılma İstekleri', style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          if (_pendingJoins.isEmpty) Text('Bekleyen istek yok.', style: TextStyle(color: PhotonColors.textDim, fontSize: 13)),
          ..._pendingJoins.map((req) => ListTile(
            title: Text(req['fromName'] as String? ?? 'Bilinmeyen', style: TextStyle(color: PhotonColors.text, fontSize: 14)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: Icon(Icons.check, color: PhotonColors.accent), onPressed: () { _acceptMember(req); set(() {}); }),
              IconButton(icon: Icon(Icons.close, color: PhotonColors.danger), onPressed: () { _rejectMember(req); set(() {}); }),
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
      backgroundColor: PhotonColors.panel,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off, color: PhotonColors.accent),
              title: Text(isMuted ? '${member.name} susturmayı kaldır' : '${member.name} kullanıcısını sustur',
                  style: TextStyle(color: PhotonColors.text)),
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
              leading: Icon(Icons.person_remove, color: PhotonColors.danger),
              title: Text('${member.name} kullanıcısını gruptan at', style: TextStyle(color: PhotonColors.danger)),
              onTap: () {
                Navigator.pop(context);
                _kickMember(member);
              },
            ),
            ListTile(
              leading: Icon(Icons.cancel_outlined, color: PhotonColors.textDim),
              title: Text('Vazgeç', style: TextStyle(color: PhotonColors.textDim)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo() {
    showModalBottomSheet(
      context: context, backgroundColor: PhotonColors.panel,
      builder: (_) => ListView(padding: const EdgeInsets.all(20), children: [
        Text(widget.group.name, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
        if (widget.group.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(widget.group.description, style: TextStyle(color: PhotonColors.textDim, fontSize: 13, height: 1.5)),
        ],
        const SizedBox(height: 6),
        if (widget.group.isOwner) ...[
          Text('GRUP ADRESİ', style: TextStyle(color: PhotonColors.textDim, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: widget.group.address)),
            child: Text(widget.group.address, style: TextStyle(color: PhotonColors.accent, fontSize: 12, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 16),
        ],
        Text('ÜYELER', style: TextStyle(color: PhotonColors.textDim, fontSize: 10, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        ...widget.group.members.map((m) {
          final isMuted = _mutedMembers.contains(m.fipId);
          final isOwner = m.fipId == widget.group.ownerFipId;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(children: [
              Text(m.name, style: TextStyle(color: PhotonColors.text, fontSize: 13)),
              if (isOwner) const SizedBox(width: 6),
              if (isOwner) Text('(sahip)', style: TextStyle(color: PhotonColors.textDim, fontSize: 10)),
              if (isMuted) const SizedBox(width: 6),
              if (isMuted) Icon(Icons.volume_off, color: PhotonColors.textDim, size: 13),
            ]),
            trailing: widget.group.isOwner && !isOwner
                ? IconButton(
                    icon: Icon(Icons.more_vert, color: PhotonColors.textDim, size: 18),
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

  void _showInviteLink() {
    final link = 'photon://${widget.group.address}';
    showModalBottomSheet(
      context: context,
      backgroundColor: PhotonColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Davet Linki', style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PhotonColors.bg,
                  border: Border.all(color: PhotonColors.accent.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(link, style: TextStyle(color: PhotonColors.accent, fontSize: 13, fontFamily: 'monospace')),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: photonPrimaryButtonStyle(),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Kopyala'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      Navigator.pop(context);
                      _showToast('Link kopyalandı!');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PhotonColors.accent,
                      side: BorderSide(color: PhotonColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Paylaş'),
                    onPressed: () {
                      Navigator.pop(context);
                      Share.share('Photon Chat grup davet linki:\n$link');
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSenderInitials(String fromName) {
    final initial = fromName.isNotEmpty ? fromName[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 14,
      backgroundColor: PhotonColors.accent.withOpacity(0.2),
      child: Text(initial, style: TextStyle(color: PhotonColors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _showAnnounceDialog() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: PhotonColors.panel,
      title: Text('Duyuru Gönder', style: TextStyle(color: PhotonColors.text, fontSize: 15)),
      content: TextField(
        controller: ctrl, autofocus: true,
        style: TextStyle(color: PhotonColors.text),
        maxLines: 3,
        decoration: InputDecoration(hintText: 'Duyuru metni…', hintStyle: TextStyle(color: PhotonColors.textDim), filled: true, fillColor: PhotonColors.bg, border: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: PhotonColors.textDim))),
        ElevatedButton(
          style: photonPrimaryButtonStyle(),
          onPressed: () async {
            Navigator.pop(ctx);
            if (ctrl.text.trim().isEmpty) return;
            await PhotonApi.sendGroupAnnouncement(widget.myServerUrl, widget.group.groupId,
              from: widget.identity.fipId, fromName: widget.displayName, text: ctrl.text.trim());
            _showToast('Duyuru gönderildi.');
          },
          child: const Text('Gönder'),
        ),
      ],
    ));
  }

  void _showPollDialog() {
    final questionCtrl = TextEditingController();
    final optCtrls = [
      TextEditingController(text: 'Evet'),
      TextEditingController(text: 'Hayır'),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return AlertDialog(
          backgroundColor: PhotonColors.panel,
          title: Text('Anket Oluştur', style: TextStyle(color: PhotonColors.text, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: questionCtrl,
                autofocus: true,
                style: TextStyle(color: PhotonColors.text),
                decoration: InputDecoration(
                  hintText: 'Soru…',
                  hintStyle: TextStyle(color: PhotonColors.textDim),
                  filled: true, fillColor: PhotonColors.bg,
                  border: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line)),
                ),
              ),
              const SizedBox(height: 12),
              ...List.generate(optCtrls.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: optCtrls[i],
                      style: TextStyle(color: PhotonColors.text),
                      decoration: InputDecoration(
                        labelText: 'Seçenek ${i + 1}${i < 2 ? "" : " (opsiyonel)"}',
                        labelStyle: TextStyle(color: PhotonColors.textDim),
                        filled: true, fillColor: PhotonColors.bg,
                        border: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line)),
                      ),
                    ),
                  ),
                  if (i >= 2) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => ss(() { optCtrls[i].dispose(); optCtrls.removeAt(i); }),
                      child: Icon(Icons.remove_circle_outline, color: PhotonColors.danger, size: 22),
                    ),
                  ],
                ]),
              )),
              TextButton.icon(
                onPressed: () => ss(() => optCtrls.add(TextEditingController())),
                icon: Icon(Icons.add, color: PhotonColors.accent, size: 18),
                label: Text('Seçenek Ekle', style: TextStyle(color: PhotonColors.accent, fontSize: 13)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: PhotonColors.textDim))),
            ElevatedButton(
              style: photonPrimaryButtonStyle(),
              onPressed: () async {
                Navigator.pop(ctx);
                final opts = optCtrls.map((c) => c.text.trim()).where((o) => o.isNotEmpty).toList();
                if (questionCtrl.text.trim().isEmpty || opts.length < 2) return;
                final memberUrls = widget.group.members.map((m) => m.serverUrl).toList()..add(widget.myServerUrl);
                await PhotonApi.sendGroupPoll(memberUrls, widget.group.groupId,
                  from: widget.identity.fipId, fromName: widget.displayName,
                  question: questionCtrl.text.trim(), options: opts, ts: DateTime.now().millisecondsSinceEpoch);
                _showToast('Anket gönderildi.');
              },
              child: const Text('Oluştur'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildPollMessage(Map<String, dynamic> m) {
    final question = m['question'] as String? ?? '';
    final options = List<String>.from(m['options'] as List? ?? []);
    final votes = Map<String, dynamic>.from(m['votes'] as Map? ?? {});
    final totalVotes = votes.length;
    final myVote = votes[widget.identity.fipId];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.accent.withOpacity(0.4)), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.poll, color: PhotonColors.accent, size: 14),
          const SizedBox(width: 6),
          Text('ANKET', style: TextStyle(color: PhotonColors.accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(width: 6),
          Text(m['fromName'] as String? ?? '', style: TextStyle(color: PhotonColors.textDim, fontSize: 10)),
        ]),
        const SizedBox(height: 8),
        Text(question, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        ...options.asMap().entries.map((entry) {
          final optionVotes = votes.values.where((v) => v == entry.key).length;
          final pct = totalVotes == 0 ? 0.0 : optionVotes / totalVotes;
          final isSelected = myVote == entry.key;
          return GestureDetector(
            onTap: myVote == null ? () => _vote(m, entry.key) : null,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: Stack(children: [
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected ? PhotonColors.accent.withOpacity(0.15) : PhotonColors.panelAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? PhotonColors.accent : PhotonColors.line),
                  ),
                ),
                if (totalVotes > 0)
                  FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: PhotonColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    Expanded(child: Text(entry.value, style: TextStyle(color: PhotonColors.text, fontSize: 13))),
                    Text('${(pct * 100).toStringAsFixed(0)}%  $optionVotes', style: TextStyle(color: PhotonColors.textDim, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
          );
        }).toList(),
        const SizedBox(height: 4),
        Text('$totalVotes oy kullandı', style: TextStyle(color: PhotonColors.textDim, fontSize: 10)),
      ]),
    );
  }

  List<QueuedMessage> get _queuedGroupMessages {
    final queued = OfflineQueue.instance.getForChat(widget.group.groupId);
    final existingTs = _messages.map((m) => m['ts'] as int).toSet();
    return queued.where((q) => !existingTs.contains(q.ts)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final myFipId = widget.identity.fipId;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (widget.group.description.isNotEmpty)
              Text(widget.group.description, style: TextStyle(fontSize: 11, color: PhotonColors.textDim, fontWeight: FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            color: PhotonColors.panel,
            icon: Icon(Icons.more_vert, color: PhotonColors.text),
            onSelected: (v) {
              if (v == 'announce') _showAnnounceDialog();
              if (v == 'poll') _showPollDialog();
              if (v == 'invite') _showInviteLink();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'invite', child: Row(children: [Icon(Icons.link, color: PhotonColors.accent, size: 16), SizedBox(width: 8), Text('Davet Linki', style: TextStyle(color: PhotonColors.text))])),
              if (widget.group.isOwner) ...[
                PopupMenuItem(value: 'announce', child: Row(children: [Icon(Icons.campaign, color: PhotonColors.accent2, size: 16), SizedBox(width: 8), Text('Duyuru Gönder', style: TextStyle(color: PhotonColors.text))])),
                PopupMenuItem(value: 'poll', child: Row(children: [Icon(Icons.poll, color: PhotonColors.accent, size: 16), SizedBox(width: 8), Text('Anket Oluştur', style: TextStyle(color: PhotonColors.text))])),
              ],
            ],
          ),
          if (widget.group.isOwner && _pendingJoins.isNotEmpty)
            Stack(children: [
              IconButton(icon: Icon(Icons.person_add, color: PhotonColors.text), onPressed: _showJoinRequests),
              Positioned(top: 8, right: 8, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: PhotonColors.accent2, shape: BoxShape.circle))),
            ])
          else if (widget.group.isOwner)
            IconButton(icon: Icon(Icons.person_add, color: PhotonColors.textDim), onPressed: _showJoinRequests),
          IconButton(icon: Icon(Icons.info_outline, color: PhotonColors.text), onPressed: _showInfo),
        ],
      ),
      backgroundColor: PhotonColors.bg,
      body: Stack(
        children: [
          ChatWallpaper.buildBackground(),
          Column(
            children: [
              // Announcements banner
              if (_announcements.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _annExpanded = !_annExpanded),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: PhotonColors.accent2.withOpacity(0.1), border: Border(bottom: BorderSide(color: PhotonColors.accent2.withOpacity(0.3)))),
                    child: Row(children: [
                      Icon(Icons.campaign, color: PhotonColors.accent2, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        _annExpanded
                          ? _announcements.map((a) => '${a['fromName']}: ${a['text']}').join('\n')
                          : _announcements.last['text'] as String,
                        style: TextStyle(color: PhotonColors.text, fontSize: 12),
                        maxLines: _annExpanded ? null : 1, overflow: _annExpanded ? null : TextOverflow.ellipsis,
                      )),
                      Icon(_annExpanded ? Icons.expand_less : Icons.expand_more, color: PhotonColors.accent2, size: 16),
                    ]),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length + _queuedGroupMessages.length,
                  itemBuilder: (_, i) {
                    if (i >= _messages.length) {
                      final q = _queuedGroupMessages[i - _messages.length];
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: PhotonColors.accent.withOpacity(0.12),
                            border: Border.all(color: PhotonColors.accent.withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(q.text, style: TextStyle(color: PhotonColors.text, fontSize: 14)),
                            const SizedBox(height: 2),
                            Icon(Icons.access_time, color: PhotonColors.textDim, size: 11),
                          ]),
                        ),
                      );
                    }
                    final m = _messages[i];
                    // Poll type
                    if (m['type'] == 'poll') {
                      return _buildPollMessage(m);
                    }
                    final isMe = m['from'] == myFipId;
                    final msgId = m['msgId'] as String? ?? '';
                    final rawText = m['text'] as String? ?? '';
                    String displayText;
                    if (_filtered.containsKey(msgId)) {
                      displayText = _filtered[msgId]!;
                    } else {
                      displayText = filterProfanity(rawText);
                      if (displayText == rawText) {
                        filterProfanityAsync(rawText).then((v) {
                          if (v != rawText && mounted) setState(() => _filtered[msgId] = v);
                        });
                      } else {
                        _filtered[msgId] = displayText;
                      }
                    }
                    final fromName = m['fromName'] as String? ?? '';
                    return GestureDetector(
                      onLongPress: () => _onLongPressGroupMessage(m),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isMe) ...[
                              _buildSenderInitials(fromName),
                              const SizedBox(width: 6),
                            ],
                            Flexible(child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
                          decoration: BoxDecoration(
                            color: isMe ? PhotonColors.accent.withOpacity(0.18) : PhotonColors.panel,
                            border: Border.all(color: isMe ? PhotonColors.accent.withOpacity(0.3) : PhotonColors.line),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                            if (!isMe) Text(fromName, style: TextStyle(color: PhotonColors.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                            Text(displayText, style: TextStyle(color: PhotonColors.text, fontSize: 14)),
                            if (_translating.contains(msgId))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: PhotonColors.textDim)),
                              ),
                            if (_translations.containsKey(msgId))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('çeviri', style: TextStyle(color: PhotonColors.textDim, fontSize: 9, fontStyle: FontStyle.italic)),
                                  const SizedBox(height: 2),
                                  Text(_translations[msgId]!,
                                    style: TextStyle(color: PhotonColors.text.withOpacity(0.8), fontSize: 13, height: 1.4, fontStyle: FontStyle.italic)),
                                ]),
                              ),
                          ]),
                        )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_inputError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: PhotonColors.danger.withOpacity(0.1),
                  child: Text(_inputError!, style: TextStyle(color: PhotonColors.danger, fontSize: 12)),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: PhotonColors.line))),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      style: TextStyle(color: PhotonColors.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Mesaj yaz…',
                        hintStyle: TextStyle(color: PhotonColors.textDim, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line), borderRadius: BorderRadius.circular(20)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.accent), borderRadius: BorderRadius.circular(20)),
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
                      decoration: BoxDecoration(color: PhotonColors.accent, shape: BoxShape.circle),
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
                decoration: BoxDecoration(color: PhotonColors.panelAlt, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(8)),
                child: Text(_toastMsg!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: PhotonColors.text)),
              ),
            ),
        ],
      ),
    );
  }
}
