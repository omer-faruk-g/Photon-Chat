import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';
import '../app_keys.dart';
import 'add_contact_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'group_chat_screen.dart';
import 'pulse_ai_screen.dart';

class ContactsScreen extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  const ContactsScreen({super.key, required this.identity, required this.displayName, required this.myServerUrl});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  List<Group> _groups = [];
  List<String> _blockList = [];
  bool _loading = true;
  String? _toast;
  final Map<String, int> _groupPendingCounts = {};
  final Map<String, bool> _online = {};

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    final savedContacts = await LocalStore.loadContacts();
    final savedGroups = await LocalStore.loadGroups();
    final blockList = await LocalStore.loadBlockList();
    setState(() { _contacts = savedContacts; _groups = savedGroups; _blockList = blockList; _loading = false; });
    final statusMsg = await LocalStore.loadStatusMsg();
    final avatar = await LocalStore.loadAvatar();
    await KnkApi.registerPresence(widget.myServerUrl, widget.identity.fipId, widget.identity.code, widget.displayName, statusMsg: statusMsg, avatar: avatar);
    _sync();
    _groupSync();
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _toast = null); });
  }

  Future<void> _sync() async {
    final me = widget.identity;
    final incoming = await KnkApi.getIncomingRequests(widget.myServerUrl, me.fipId);
    for (final req in incoming) {
      final fromFipId = req['fromFipId'] as String;
      // Engellenen kişilerden gelen istekleri filtrele
      if (_blockList.contains(fromFipId)) continue;
      final fromServerUrl = (req['fromServerUrl'] as String?) ?? '';
      if (!_contacts.any((c) => c.fipId == fromFipId)) {
        _contacts.add(Contact(fipId: fromFipId, name: (req['fromName'] as String?) ?? 'Bilinmeyen',
            code: (req['fromCode'] as String?) ?? '?????', serverUrl: fromServerUrl, status: 'pending_in'));
      }
    }
    final accepted = await KnkApi.getAcceptedRequests(widget.myServerUrl, me.fipId);
    for (final fipId in accepted) {
      final idx = _contacts.indexWhere((c) => c.fipId == fipId);
      if (idx != -1 && _contacts[idx].status == 'pending_out') _contacts[idx].status = 'on';
    }
    for (final c in _contacts.where((c) => c.status == 'on').toList()) {
      final active = await KnkApi.isActive(c.serverUrl, c.fipId);
      if (!active) { _contacts.removeWhere((x) => x.fipId == c.fipId); _online.remove(c.fipId); _showToast('${c.name} ile bağlantı sonlandı.'); continue; }
      _online[c.fipId] = true;
      // Profil bilgilerini güncelle (avatar, statusMsg, lastSeen)
      final profile = await KnkApi.getProfile(c.serverUrl, c.fipId);
      if (profile != null) {
        c.avatar = (profile['avatar'] as String?) ?? '';
        c.statusMsg = (profile['statusMsg'] as String?) ?? '';
        c.lastSeen = (profile['lastSeen'] as int?) ?? 0;
      }
    }
    await LocalStore.saveContacts(_contacts);
    if (mounted) setState(() {});
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) _sync();
  }

  Future<void> _groupSync() async {
    for (final g in _groups.where((g) => g.isOwner)) {
      try {
        final reqs = await KnkApi.getGroupJoinRequests(widget.myServerUrl, g.groupId);
        if (mounted) setState(() => _groupPendingCounts[g.groupId] = reqs.length);
      } catch (_) {}
    }
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) _groupSync();
  }

  Future<void> _accept(Contact c) async {
    setState(() => c.status = 'on');
    await LocalStore.saveContacts(_contacts);
    await KnkApi.acceptFriendRequest(myServerUrl: widget.myServerUrl, myFipId: widget.identity.fipId, otherFipId: c.fipId);
    _showToast('${c.name} arkadaş listene eklendi.');
  }

  Future<void> _decline(Contact c) async {
    setState(() => _contacts.removeWhere((x) => x.fipId == c.fipId));
    await LocalStore.saveContacts(_contacts);
  }

  Future<void> _blockContact(Contact c) async {
    await LocalStore.blockUser(c.fipId);
    setState(() {
      _blockList.add(c.fipId);
      _contacts.removeWhere((x) => x.fipId == c.fipId);
    });
    await LocalStore.saveContacts(_contacts);
    _showToast('${c.name} engellendi.');
  }

  Future<void> _openAddScreen() async {
    final result = await Navigator.push<Contact>(context, MaterialPageRoute(
      builder: (_) => AddContactScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (result != null) {
      setState(() => _contacts.add(result));
      await LocalStore.saveContacts(_contacts);
      _showToast('${result.name} kullanıcısına davet gönderildi.');
    }
  }

  Future<void> _openCreateGroup() async {
    final result = await Navigator.push<Group>(context, MaterialPageRoute(
      builder: (_) => CreateGroupScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (result != null) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('Grup oluşturuldu: ${result.name}');
    }
  }

  Future<void> _openJoinGroup() async {
    final result = await Navigator.push<Group>(context, MaterialPageRoute(
      builder: (_) => JoinGroupScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (result != null) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('${result.name} grubuna katılma isteği gönderildi.');
    }
  }

  void _openGroupChat(Group g) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GroupChatScreen(group: g, identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
  }

  void _openChat(Contact c) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(identity: widget.identity, contact: c, myServerUrl: widget.myServerUrl)));
  }

  void _openPulseAI() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PulseAiScreen(myServerUrl: widget.myServerUrl)));
  }

  void _openSettings() async {
    final deactivated = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SettingsScreen(identity: widget.identity, myServerUrl: widget.myServerUrl, displayName: widget.displayName)));
    if (deactivated == true && mounted) {
      (rootGateKey.currentState as dynamic)?.reload();
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  Future<void> _handleExit(List<Contact> active) async {
    if (active.isEmpty) { SystemNavigator.pop(); return; }
    final keep = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: Text('Sohbetler kaydedilsin mi?', style: TextStyle(color: KnkColors.text, fontSize: 15)),
        content: Text('Hayır derseniz kendi sunucunuzdaki sohbet geçmişleri silinir.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Hayır, imha et', style: TextStyle(color: KnkColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Evet, sakla', style: TextStyle(color: KnkColors.accent))),
        ],
      ),
    );
    if (keep == false) {
      for (final c in active) await KnkApi.deleteChat(widget.myServerUrl, chatKeyFor(widget.identity.fipId, c.fipId));
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(body: Center(child: CircularProgressIndicator(color: KnkColors.accent)));
    final incoming = _contacts.where((c) => c.status == 'pending_in').toList();
    final outgoing = _contacts.where((c) => c.status == 'pending_out').toList();
    final active = _contacts.where((c) => c.status == 'on').toList();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async { if (!didPop) await _handleExit(active); },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kişiler'),
          leading: Tooltip(
            message: 'Senin 5 haneli kodun — tıkla, kopyala',
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.identity.code));
                _showToast('Kodun kopyalandı: ${widget.identity.code}');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('KODUM', style: TextStyle(color: KnkColors.textDim, fontSize: 7, letterSpacing: 1.2)),
                    const SizedBox(height: 1),
                    Text(widget.identity.code, style: TextStyle(color: KnkColors.accent, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
          ),
          actions: [IconButton(icon: Icon(Icons.settings, color: KnkColors.text), onPressed: _openSettings)],
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // Pulse AI sabitlenmiş kart
                _PulseAiCard(onTap: _openPulseAI),
                const SizedBox(height: 20),
                if (incoming.isNotEmpty) ...[
                  _SectionTitle('Davetler · ${incoming.length}'),
                  ...incoming.map((c) => _RequestRow(contact: c, onAccept: () => _accept(c), onDecline: () => _decline(c))),
                  const SizedBox(height: 16),
                ],
                _SectionTitle('Kişiler · ${active.length}'),
                if (active.isEmpty && outgoing.isEmpty && incoming.isEmpty) _EmptyState(onAdd: _openAddScreen),
                ...active.map((c) => _ContactRow(
                  contact: c,
                  isOnline: _online[c.fipId] ?? false,
                  onTap: () => _openChat(c),
                  onBlock: () => _blockContact(c),
                )),
                ...outgoing.map((c) => _PendingOutRow(contact: c)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _SectionTitle('Gruplar · ${_groups.length}')),
                    _GroupActionButton(label: '+ Oluştur', onTap: _openCreateGroup),
                    const SizedBox(width: 8),
                    _GroupActionButton(label: '+ Katıl', onTap: _openJoinGroup),
                  ],
                ),
                if (_groups.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(10)),
                    child: Text('Henüz bir grubun yok.\nYeni grup oluştur veya mevcut bir gruba katıl.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6)),
                  ),
                ..._groups.map((g) => _GroupRow(group: g, pendingCount: _groupPendingCounts[g.groupId] ?? 0, onTap: () => _openGroupChat(g))),
              ],
            ),
            Positioned(
              left: 16, right: 16, bottom: 20,
              child: ElevatedButton(style: knkPrimaryButtonStyle(), onPressed: _openAddScreen, child: const Text('+ Kişi ekle')),
            ),
            if (_toast != null)
              Positioned(
                left: 16, right: 16, bottom: 84,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: KnkColors.panelAlt, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
                  child: Text(_toast!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: KnkColors.text)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PulseAiCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PulseAiCard({required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KnkColors.accent.withOpacity(0.07),
        border: Border.all(color: KnkColors.accent.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KnkColors.accent.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: KnkColors.accent.withOpacity(0.4)),
            ),
            child: const Text('⚡', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pulse AI', style: TextStyle(color: KnkColors.accent, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Yapay zeka asistanın · Sor, sohbet et', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
          ])),
          Icon(Icons.chevron_right, color: KnkColors.accent, size: 20),
        ],
      ),
    ),
  );
}

class _GroupActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GroupActionButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: KnkColors.accent.withOpacity(0.5)), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: KnkColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
    ),
  );
}

class _GroupRow extends StatelessWidget {
  final Group group;
  final int pendingCount;
  final VoidCallback onTap;
  const _GroupRow({required this.group, required this.pendingCount, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(color: KnkColors.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.group, color: KnkColors.accent, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
          Text(group.isOwner ? 'Sahip · ${group.groupCode}' : 'Üye · ${group.groupCode}', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
        ])),
        if (pendingCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: KnkColors.accent2, borderRadius: BorderRadius.circular(12)),
            child: Text('$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, color: KnkColors.textDim),
      ]),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(text.toUpperCase(), style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5)),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
    decoration: BoxDecoration(border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text('＋', style: TextStyle(color: KnkColors.accent2, fontSize: 28)),
      const SizedBox(height: 8),
      Text('Rehberin boş', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: KnkColors.text)),
      const SizedBox(height: 6),
      Text('Arkadaşının 5 haneli kodunu girerek kişi ekle.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6)),
      const SizedBox(height: 16),
      ElevatedButton(style: knkPrimaryButtonStyle(), onPressed: onAdd, child: const Text('Kişi ekle')),
    ]),
  );
}

class _RequestRow extends StatelessWidget {
  final Contact contact;
  final VoidCallback onAccept, onDecline;
  const _RequestRow({required this.contact, required this.onAccept, required this.onDecline});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: KnkColors.panelAlt, border: Border.all(color: KnkColors.accent2.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      _Avatar(name: contact.name, on: false, avatar: contact.avatar), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(contact.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
        Text('kod ${contact.code}', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
      ])),
      Column(children: [
        SizedBox(height: 30, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: KnkColors.accent, foregroundColor: const Color(0xFF06251A), padding: const EdgeInsets.symmetric(horizontal: 10), textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          onPressed: onAccept, child: const Text('Kabul et'),
        )),
        const SizedBox(height: 4),
        SizedBox(height: 26, child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: KnkColors.textDim, side: BorderSide(color: KnkColors.line), padding: const EdgeInsets.symmetric(horizontal: 10), textStyle: TextStyle(fontSize: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          onPressed: onDecline, child: const Text('Sil'),
        )),
      ]),
    ]),
  );
}

class _ContactRow extends StatelessWidget {
  final Contact contact;
  final bool isOnline;
  final VoidCallback onTap;
  final VoidCallback onBlock;
  const _ContactRow({required this.contact, required this.isOnline, required this.onTap, required this.onBlock});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () {
      showModalBottomSheet(
        context: context,
        backgroundColor: KnkColors.panel,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.block, color: KnkColors.danger),
                title: Text('${contact.name} kullanıcısını engelle', style: TextStyle(color: KnkColors.danger)),
                onTap: () {
                  Navigator.pop(context);
                  onBlock();
                },
              ),
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: KnkColors.textDim),
                title: Text('Vazgeç', style: TextStyle(color: KnkColors.textDim)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    },
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Stack(children: [
            _Avatar(name: contact.name, on: true, avatar: contact.avatar),
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 11, height: 11,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : KnkColors.textDim,
                  shape: BoxShape.circle,
                  border: Border.all(color: KnkColors.panel, width: 1.5),
                ),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(contact.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
            Text(
              isOnline ? 'Çevrimiçi' : (contact.statusMsg.isNotEmpty ? contact.statusMsg : 'çevrimdışı'),
              style: TextStyle(color: isOnline ? Colors.green : KnkColors.textDim, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ])),
          Icon(Icons.chevron_right, color: KnkColors.textDim),
        ]),
      ),
    ),
  );
}

class _PendingOutRow extends StatelessWidget {
  final Contact contact;
  const _PendingOutRow({required this.contact});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      _Avatar(name: contact.name, on: false, avatar: contact.avatar), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(contact.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
        Text('davet gönderildi · onay bekleniyor', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
      ])),
    ]),
  );
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool on;
  final String avatar;
  const _Avatar({required this.name, required this.on, this.avatar = ''});
  @override
  Widget build(BuildContext context) {
    if (avatar.isNotEmpty) {
      try {
        final bytes = base64Decode(avatar);
        return Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: on ? Border.all(color: KnkColors.accent.withOpacity(0.5), width: 2) : null,
            image: DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
        );
      } catch (_) {}
    }
    final initials = name.trim().isEmpty ? '?' : name.trim().substring(0, name.trim().length >= 2 ? 2 : 1).toUpperCase();
    return Container(
      width: 38, height: 38, alignment: Alignment.center,
      decoration: BoxDecoration(color: KnkColors.line, borderRadius: BorderRadius.circular(8), border: on ? Border.all(color: KnkColors.accent.withOpacity(0.5)) : null),
      child: Text(initials, style: TextStyle(color: on ? KnkColors.accent : KnkColors.textDim, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
