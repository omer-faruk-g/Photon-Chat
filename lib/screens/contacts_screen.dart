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
  bool _loading = true;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final savedContacts = await LocalStore.loadContacts();
    final savedGroups = await LocalStore.loadGroups();
    setState(() {
      _contacts = savedContacts;
      _groups = savedGroups;
      _loading = false;
    });
    await KnkApi.registerPresence(widget.myServerUrl, widget.identity.fipId, widget.identity.code, widget.displayName);
    _sync();
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _sync() async {
    final me = widget.identity;

    // 1) gelen istekler
    final incoming = await KnkApi.getIncomingRequests(widget.myServerUrl, me.fipId);
    for (final req in incoming) {
      final fromFipId = req['fromFipId'] as String;
      final exists = _contacts.any((c) => c.fipId == fromFipId);
      if (!exists) {
        _contacts.add(Contact(
          fipId: fromFipId,
          name: (req['fromName'] as String?) ?? 'Bilinmeyen',
          code: (req['fromCode'] as String?) ?? '?????',
          serverUrl: (req['fromServerUrl'] as String?) ?? '',
          status: 'pending_in',
        ));
      }
    }

    // 2) kabul edilen giden istekler
    final accepted = await KnkApi.getAcceptedRequests(widget.myServerUrl, me.fipId);
    for (final fipId in accepted) {
      final idx = _contacts.indexWhere((c) => c.fipId == fipId);
      if (idx != -1 && _contacts[idx].status == 'pending_out') {
        _contacts[idx].status = 'on';
      }
    }

    await LocalStore.saveContacts(_contacts);
    if (mounted) setState(() {});

    await Future.delayed(const Duration(seconds: 3));
    if (mounted) _sync();
  }

  Future<void> _accept(Contact c) async {
    setState(() => c.status = 'on');
    await LocalStore.saveContacts(_contacts);
    await KnkApi.acceptFriendRequest(myServerUrl: widget.myServerUrl, myFipId: widget.identity.fipId, otherFipId: c.fipId);
    _showToast('${c.name} artık arkadaş listende.');
  }

  Future<void> _decline(Contact c) async {
    setState(() => _contacts.removeWhere((x) => x.fipId == c.fipId));
    await LocalStore.saveContacts(_contacts);
  }

  Future<void> _openAddScreen() async {
    final result = await Navigator.push<Contact>(
      context,
      MaterialPageRoute(
        builder: (_) => AddContactScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
      ),
    );
    if (result != null) {
      setState(() => _contacts.add(result));
      await LocalStore.saveContacts(_contacts);
      _showToast('${result.name} kullanıcısına davet gönderildi.');
    }
  }

  void _openChat(Contact c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(identity: widget.identity, contact: c, myServerUrl: widget.myServerUrl),
      ),
    );
  }

  void _openSettings() async {
    final deactivated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(identity: widget.identity, myServerUrl: widget.myServerUrl),
      ),
    );
    if (deactivated == true && mounted) {
      (rootGateKey.currentState as dynamic)?.reload();
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  Future<void> _openCreateGroup() async {
    final result = await Navigator.push<Group>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
      ),
    );
    if (result != null) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('Grup “${result.name}” oluşturuldu.');
    }
  }

  Future<void> _openJoinGroup() async {
    final result = await Navigator.push<Group>(
      context,
      MaterialPageRoute(
        builder: (_) => JoinGroupScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
      ),
    );
    if (result != null) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('Gruba katılma isteği gönderildi.');
    }
  }

  void _openGroupChat(Group g) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(group: g, identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
      ),
    );
  }

  Future<void> _handleExitRequest(List<Contact> activeContacts) async {
    if (activeContacts.isEmpty) {
      SystemNavigator.pop();
      return;
    }

    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: const Text('Sohbetler kaydedilsin mi?', style: TextStyle(color: KnkColors.text, fontSize: 15)),
        content: const Text(
          'Uygulamadan çıkıyorsun. Sohbet geçmişlerin sunucuda saklansin mi, '
          'yoksa şimdi kalıcı olarak imha edilsin mi?\n\n'
          'İmha edilirse, karşı taraf tekrar girdiğinde sohbet temiz görünür ve '
          'bu işlem hiçbir yerde loglanmaz.',
          style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır, imha et', style: TextStyle(color: KnkColors.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet, sakla', style: TextStyle(color: KnkColors.accent)),
          ),
        ],
      ),
    );

    if (keep == false) {
      for (final c in activeContacts) {
        final ck = chatKeyFor(widget.identity.fipId, c.fipId);
        await KnkApi.deleteChat(widget.myServerUrl, ck);
      }
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: KnkColors.accent)));
    }

    final incoming = _contacts.where((c) => c.status == 'pending_in').toList();
    final outgoing = _contacts.where((c) => c.status == 'pending_out').toList();
    final active = _contacts.where((c) => c.status == 'on').toList();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleExitRequest(active);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kişiler'),
          leading: Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: '${widget.identity.code}@${widget.myServerUrl}')),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: KnkColors.accent.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.identity.code,
                  style: const TextStyle(color: KnkColors.accent, fontSize: 10, letterSpacing: 1.5),
                ),
              ),
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: KnkColors.text),
              color: KnkColors.panel,
              onSelected: (v) {
                if (v == 'settings') _openSettings();
                if (v == 'create_group') _openCreateGroup();
                if (v == 'join_group') _openJoinGroup();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'create_group', child: Text('Grup Oluştur', style: TextStyle(color: KnkColors.text, fontSize: 13))),
                const PopupMenuItem(value: 'join_group', child: Text('Gruba Katıl', style: TextStyle(color: KnkColors.text, fontSize: 13))),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'settings', child: Text('Ayarlar', style: TextStyle(color: KnkColors.text, fontSize: 13))),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                if (incoming.isNotEmpty) ...[
                  _SectionTitle('Davetler · ${incoming.length}'),
                  ...incoming.map((c) => _RequestRow(contact: c, onAccept: () => _accept(c), onDecline: () => _decline(c))),
                  const SizedBox(height: 16),
                ],
                _SectionTitle('Kişiler · ${active.length}'),
                if (active.isEmpty && outgoing.isEmpty && incoming.isEmpty)
                  _EmptyState(onAdd: _openAddScreen),
                ...active.map((c) => _ContactRow(contact: c, onTap: () => _openChat(c))),
                ...outgoing.map((c) => _PendingOutRow(contact: c)),
                if (_groups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle('Gruplar · ${_groups.length}'),
                  ..._groups.map((g) => _GroupRow(group: g, onTap: () => _openGroupChat(g))),
                ],
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: ElevatedButton(
                style: knkPrimaryButtonStyle(),
                onPressed: _openAddScreen,
                child: const Text('+ Kişi ekle'),
              ),
            ),
            if (_toast != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 84,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: KnkColors.panelAlt,
                    border: Border.all(color: KnkColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_toast!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: KnkColors.text)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: KnkColors.line, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text('＋', style: TextStyle(color: KnkColors.accent2, fontSize: 28)),
          const SizedBox(height: 8),
          const Text('Rehberin boş',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: KnkColors.text)),
          const SizedBox(height: 6),
          const Text(
            'Bir arkadaşının adresini gir (KOD@SUNUCU), davet gönder. Kabul ettiğinde '
            'burada görünür ve özel sohbet açılır.',
            textAlign: TextAlign.center,
            style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 16),
          ElevatedButton(style: knkPrimaryButtonStyle(), onPressed: onAdd, child: const Text('Kişi ekle')),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final Contact contact;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestRow({required this.contact, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KnkColors.panelAlt,
        border: Border.all(color: KnkColors.accent2.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Avatar(name: contact.name, on: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
                const SizedBox(height: 2),
                Text('kod ${contact.code} · arkadaşlık daveti gönderdi',
                    style: const TextStyle(color: KnkColors.textDim, fontSize: 11)),
              ],
            ),
          ),
          Column(
            children: [
              SizedBox(
                height: 30,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KnkColors.accent,
                    foregroundColor: const Color(0xFF06251A),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: onAccept,
                  child: const Text('Kabul et'),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 26,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KnkColors.textDim,
                    side: const BorderSide(color: KnkColors.line),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(fontSize: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: onDecline,
                  child: const Text('Sil'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;

  const _ContactRow({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KnkColors.panel,
          border: Border.all(color: KnkColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _Avatar(name: contact.name, on: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      const Text('bağlı · FIP eşleşti', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: KnkColors.textDim),
          ],
        ),
      ),
    );
  }
}

class _PendingOutRow extends StatelessWidget {
  final Contact contact;
  const _PendingOutRow({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KnkColors.panel,
        border: Border.all(color: KnkColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Avatar(name: contact.name, on: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: const BoxDecoration(color: KnkColors.textDim, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    const Text('davet gönderildi · onay bekleniyor', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final Group group;
  final VoidCallback onTap;
  const _GroupRow({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KnkColors.panel,
          border: Border.all(color: KnkColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: KnkColors.line,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KnkColors.accent2.withOpacity(0.4)),
              ),
              child: const Text('👥', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
                  const SizedBox(height: 2),
                  Text(
                    group.isOwner ? 'Sahip · ${group.members.length} üye' : 'Grup · ${group.ownerServerUrl}',
                    style: const TextStyle(color: KnkColors.textDim, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: KnkColors.textDim),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool on;
  const _Avatar({required this.name, required this.on});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty ? '?' : name.trim().substring(0, name.trim().length >= 2 ? 2 : 1).toUpperCase();
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KnkColors.line,
        borderRadius: BorderRadius.circular(8),
        border: on ? Border.all(color: KnkColors.accent.withOpacity(0.5)) : null,
      ),
      child: Text(initials, style: TextStyle(color: on ? KnkColors.accent : KnkColors.textDim, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
