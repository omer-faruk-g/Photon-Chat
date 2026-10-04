import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../e2e.dart';
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
  Timer? _toastTimer;
  final Map<String, int> _groupPendingCounts = {};

  Timer? _syncTimer;
  Timer? _groupSyncTimer;
  bool _syncing = false;
  bool _groupSyncing = false;
  bool _disposed = false;
  DateTime _lastPresence = DateTime.fromMillisecondsSinceEpoch(0);
  String? _publicKey;
  String _authToken = '';

  static const _syncInterval = Duration(seconds: 4);
  static const _groupSyncInterval = Duration(seconds: 8);
  // Render ücretsiz sunucuları yeniden başlayınca belleği sıfırlar; kayıt düzenli yenilenir.
  static const _presenceInterval = Duration(minutes: 1);

  @override
  void initState() { super.initState(); _init(); }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _groupSyncTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final savedContacts = await LocalStore.loadContacts();
    final savedGroups = await LocalStore.loadGroups();
    final blockList = await LocalStore.loadBlockList();
    if (_disposed) return;
    setState(() { _contacts = savedContacts; _groups = savedGroups; _blockList = blockList; _loading = false; });
    try { _publicKey = await getMyPublicKeyBase64(); } catch (_) {}
    _authToken = await LocalStore.loadOrCreateAuthToken();
    await _registerPresence();
    unawaited(_sync());
    unawaited(_groupSync());
  }

  Future<void> _registerPresence() async {
    _lastPresence = DateTime.now();
    await KnkApi.registerPresence(widget.myServerUrl, widget.identity.fipId, widget.identity.code, widget.displayName,
        publicKey: _publicKey, authToken: _authToken);
  }

  void _showToast(String msg) {
    if (_disposed) return;
    _toastTimer?.cancel();
    setState(() => _toast = msg);
    _toastTimer = Timer(const Duration(seconds: 3), () { if (!_disposed) setState(() => _toast = null); });
  }

  Future<void> _saveContacts() async {
    // Hesap silindikten sonra devam eden bir senkron eski kişileri geri yazmasın.
    if (_disposed) return;
    await LocalStore.saveContacts(_contacts);
  }

  Future<void> _sync() async {
    if (_disposed || _syncing) return;
    _syncing = true;
    try {
      await _syncOnce();
    } catch (_) {
      // Tek bir hatalı yanıt senkron döngüsünü durdurmamalı.
    } finally {
      _syncing = false;
      if (!_disposed) _syncTimer = Timer(_syncInterval, _sync);
    }
  }

  Future<void> _syncOnce() async {
    final me = widget.identity;
    if (DateTime.now().difference(_lastPresence) > _presenceInterval) await _registerPresence();
    var changed = false;

    final incoming = await KnkApi.getIncomingRequests(widget.myServerUrl, me.fipId);
    if (_disposed) return;
    for (final req in incoming ?? const <Map<String, dynamic>>[]) {
      final fromFipId = req['fromFipId'];
      if (fromFipId is! String || fromFipId == me.fipId) continue;
      // Engellenen kişilerden gelen istekleri filtrele
      if (_blockList.contains(fromFipId)) continue;
      final fromServerUrl = (req['fromServerUrl'] as String?) ?? '';
      final idx = _contacts.indexWhere((c) => c.fipId == fromFipId);
      if (idx == -1) {
        _contacts.add(Contact(fipId: fromFipId, name: (req['fromName'] as String?) ?? 'Bilinmeyen',
            code: (req['fromCode'] as String?) ?? '?????', serverUrl: fromServerUrl, status: 'pending_in',
            publicKey: req['fromPublicKey'] as String?));
        changed = true;
      } else if (_contacts[idx].status == 'pending_out') {
        // İki taraf birbirine istek göndermiş: karşılıklı onay say.
        final c = _contacts[idx];
        c.status = 'on';
        c.publicKey ??= req['fromPublicKey'] as String?;
        changed = true;
        await KnkApi.acceptFriendRequest(myServerUrl: widget.myServerUrl, myFipId: me.fipId, otherFipId: c.fipId, otherServerUrl: c.serverUrl);
        _showToast('${c.name} ile bağlantı kuruldu.');
      } else if (_contacts[idx].status == 'on') {
        // Zaten arkadaşız (ör. karşı taraf isteği tekrar gönderdi): isteği temizle.
        await KnkApi.acceptFriendRequest(myServerUrl: widget.myServerUrl, myFipId: me.fipId, otherFipId: fromFipId);
      }
    }

    if (_contacts.any((c) => c.status == 'pending_out')) {
      final accepted = await KnkApi.getAcceptedRequests(widget.myServerUrl, me.fipId);
      if (_disposed) return;
      for (final fipId in accepted) {
        final idx = _contacts.indexWhere((c) => c.fipId == fipId);
        if (idx != -1 && _contacts[idx].status == 'pending_out') {
          _contacts[idx].status = 'on';
          changed = true;
          _showToast('${_contacts[idx].name} davetini kabul etti.');
        }
      }
    }

    // Bağlı kişilerin durumunu sunucu başına tek istekle kontrol et.
    // Yalnızca sunucu "hesabını sildi" derse kişi kaldırılır; ağ hatası veya
    // yeniden başlayan sunucu kişiyi asla silmez.
    final byServer = <String, List<String>>{};
    for (final c in _contacts.where((c) => c.status == 'on')) {
      byServer.putIfAbsent(c.serverUrl, () => []).add(c.fipId);
    }
    final results = await Future.wait(byServer.entries.map((e) => KnkApi.getStatuses(e.key, e.value)));
    if (_disposed) return;
    final statuses = <String, ContactStatus>{for (final r in results) ...r};
    final gone = _contacts.where((c) => c.status == 'on' && statuses[c.fipId] == ContactStatus.deactivated).toList();
    for (final c in gone) {
      _contacts.removeWhere((x) => x.fipId == c.fipId);
      changed = true;
      _showToast('${c.name} hesabını sildi, bağlantı sonlandı.');
    }

    if (changed) {
      await _saveContacts();
      if (!_disposed) setState(() {});
    }
  }

  Future<void> _groupSync() async {
    if (_disposed || _groupSyncing) return;
    _groupSyncing = true;
    try {
      final owned = _groups.where((g) => g.isOwner).toList();
      final counts = await Future.wait(owned.map((g) => KnkApi.getGroupJoinRequests(g.ownerServerUrl, g.groupId)));
      if (!_disposed) {
        var changed = false;
        for (var i = 0; i < owned.length; i++) {
          final n = counts[i]?.length;
          if (n != null && _groupPendingCounts[owned[i].groupId] != n) {
            _groupPendingCounts[owned[i].groupId] = n;
            changed = true;
          }
        }
        if (changed) setState(() {});
      }
    } catch (_) {
    } finally {
      _groupSyncing = false;
      if (!_disposed) _groupSyncTimer = Timer(_groupSyncInterval, _groupSync);
    }
  }

  Future<void> _accept(Contact c) async {
    setState(() => c.status = 'on');
    await _saveContacts();
    await KnkApi.acceptFriendRequest(myServerUrl: widget.myServerUrl, myFipId: widget.identity.fipId, otherFipId: c.fipId, otherServerUrl: c.serverUrl);
    _showToast('${c.name} arkadaş listene eklendi.');
  }

  Future<void> _decline(Contact c) async {
    setState(() => _contacts.removeWhere((x) => x.fipId == c.fipId));
    await _saveContacts();
    // Sunucudan da sil; yoksa bir sonraki senkronda istek geri gelir.
    await KnkApi.declineFriendRequest(myServerUrl: widget.myServerUrl, myFipId: widget.identity.fipId, otherFipId: c.fipId);
  }

  Future<void> _blockContact(Contact c) async {
    await LocalStore.blockUser(c.fipId);
    if (_disposed) return;
    setState(() {
      if (!_blockList.contains(c.fipId)) _blockList.add(c.fipId);
      _contacts.removeWhere((x) => x.fipId == c.fipId);
    });
    await _saveContacts();
    await KnkApi.declineFriendRequest(myServerUrl: widget.myServerUrl, myFipId: widget.identity.fipId, otherFipId: c.fipId);
    _showToast('${c.name} engellendi.');
  }

  Future<void> _openAddScreen() async {
    final result = await Navigator.push<Contact>(context, MaterialPageRoute(
      builder: (_) => AddContactScreen(
        identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl,
        existingFipIds: _contacts.map((c) => c.fipId).toSet(),
        publicKey: _publicKey,
      ),
    ));
    if (result != null && !_disposed) {
      // Engellenmiş birini bilerek tekrar eklemek engeli kaldırır.
      if (_blockList.remove(result.fipId)) await LocalStore.unblockUser(result.fipId);
      setState(() {
        _contacts.removeWhere((c) => c.fipId == result.fipId);
        _contacts.add(result);
      });
      await _saveContacts();
      _showToast('${result.name} kullanıcısına davet gönderildi.');
    }
  }

  Future<void> _openCreateGroup() async {
    final result = await Navigator.push<Group>(context, MaterialPageRoute(
      builder: (_) => CreateGroupScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (result != null && !_disposed) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('Grup oluşturuldu: ${result.name}');
    }
  }

  Future<void> _openJoinGroup() async {
    final result = await Navigator.push<Group>(context, MaterialPageRoute(
      builder: (_) => JoinGroupScreen(
        identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl,
        existingGroupIds: _groups.map((g) => g.groupId).toSet(),
      ),
    ));
    if (result != null && !_disposed) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('${result.name} grubuna katılma isteği gönderildi.');
    }
  }

  Future<void> _openGroupChat(Group g) async {
    final left = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => GroupChatScreen(group: g, identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (_disposed) return;
    if (left == true) {
      setState(() {
        _groups.removeWhere((x) => x.groupId == g.groupId);
        _groupPendingCounts.remove(g.groupId);
      });
      _showToast('${g.name} grubundan ayrıldın.');
    }
    // Üye listesi sohbet ekranında güncellenmiş olabilir.
    await LocalStore.saveGroups(_groups);
  }

  Future<void> _openChat(Contact c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(identity: widget.identity, contact: c, myServerUrl: widget.myServerUrl)));
    // Sohbette kişinin public key'i öğrenilmiş olabilir.
    await _saveContacts();
  }

  void _openPulseAI() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PulseAiScreen(myServerUrl: widget.myServerUrl)));
  }

  Future<void> _openSettings() async {
    // Hesap silinirken arka plandaki senkron durdurulur.
    final deactivated = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => SettingsScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl, onBeforeDeactivate: _stopSync),
    ));
    if (deactivated == true && mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
      (rootGateKey.currentState as dynamic)?.reload();
    }
  }

  void _stopSync() {
    _disposed = true;
    _syncTimer?.cancel();
    _groupSyncTimer?.cancel();
  }

  Future<void> _handleExit(List<Contact> active) async {
    if (active.isEmpty) { await SystemNavigator.pop(); return; }
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KnkColors.panel,
        title: const Text('Sohbetler kaydedilsin mi?', style: TextStyle(color: KnkColors.text, fontSize: 15)),
        content: const Text('Hayır derseniz kendi sunucunuzdaki sohbet geçmişleri silinir.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır, imha et', style: TextStyle(color: KnkColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, sakla', style: TextStyle(color: KnkColors.accent))),
        ],
      ),
    );
    if (keep == null) return; // diyalog kapatıldı: uygulamada kal
    if (keep == false) {
      await Future.wait(active.map((c) => KnkApi.deleteChat(widget.myServerUrl, chatKeyFor(widget.identity.fipId, c.fipId), _authToken)));
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: KnkColors.accent)));
    final incoming = _contacts.where((c) => c.status == 'pending_in').toList();
    final outgoing = _contacts.where((c) => c.status == 'pending_out').toList();
    final active = _contacts.where((c) => c.status == 'on').toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async { if (!didPop) await _handleExit(active); },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kişiler'),
          leadingWidth: 88,
          // Kendi eşleşme kodun: dokununca kopyalanır.
          leading: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Tooltip(
              message: 'Senin kodun (kopyalamak için dokun)',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: widget.identity.code));
                  _showToast('Kodun kopyalandı: ${widget.identity.code}');
                },
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(border: Border.all(color: KnkColors.accent.withOpacity(0.4)), borderRadius: BorderRadius.circular(6)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(widget.identity.code, maxLines: 1, softWrap: false,
                        style: const TextStyle(color: KnkColors.accent, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
          actions: [IconButton(tooltip: 'Ayarlar', icon: const Icon(Icons.settings, color: KnkColors.text), onPressed: _openSettings)],
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
                    child: const Text('Henüz bir grubun yok.\nYeni grup oluştur veya mevcut bir gruba katıl.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6)),
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
                  child: Text(_toast!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: KnkColors.text)),
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
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pulse AI', style: TextStyle(color: KnkColors.accent, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Yapay zeka asistanın · Sor, sohbet et', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right, color: KnkColors.accent, size: 20),
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
      child: Text(label, style: const TextStyle(color: KnkColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
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
            child: const Icon(Icons.group, color: KnkColors.accent, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
          Text(group.isOwner ? 'Sahip · ${group.groupCode}' : 'Üye · ${group.groupCode}', style: const TextStyle(color: KnkColors.textDim, fontSize: 11)),
        ])),
        if (pendingCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: KnkColors.accent2, borderRadius: BorderRadius.circular(12)),
            child: Text('$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right, color: KnkColors.textDim),
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
    child: Text(text.toUpperCase(), style: const TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5)),
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
      const Text('＋', style: TextStyle(color: KnkColors.accent2, fontSize: 28)),
      const SizedBox(height: 8),
      const Text('Rehberin boş', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: KnkColors.text)),
      const SizedBox(height: 6),
      const Text('Arkadaşının 5 haneli kodunu girerek ekle.\nKendi kodun sol üstte yazıyor.', textAlign: TextAlign.center, style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6)),
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
      _Avatar(name: contact.name, on: false), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
        Text('kod ${contact.code}', style: const TextStyle(color: KnkColors.textDim, fontSize: 11)),
      ])),
      Column(children: [
        SizedBox(height: 30, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: KnkColors.accent, foregroundColor: const Color(0xFF06251A), padding: const EdgeInsets.symmetric(horizontal: 10), textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          onPressed: onAccept, child: const Text('Kabul et'),
        )),
        const SizedBox(height: 4),
        SizedBox(height: 26, child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: KnkColors.textDim, side: const BorderSide(color: KnkColors.line), padding: const EdgeInsets.symmetric(horizontal: 10), textStyle: const TextStyle(fontSize: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          onPressed: onDecline, child: const Text('Sil'),
        )),
      ]),
    ]),
  );
}

class _ContactRow extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onBlock;
  const _ContactRow({required this.contact, required this.onTap, required this.onBlock});

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KnkColors.panel,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block, color: KnkColors.danger),
              title: Text('${contact.name} kullanıcısını engelle', style: const TextStyle(color: KnkColors.danger)),
              onTap: () {
                Navigator.pop(sheetCtx);
                onBlock();
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: KnkColors.panel,
      shape: RoundedRectangleBorder(side: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showMenu(context),
        onSecondaryTap: () => _showMenu(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(children: [
            _Avatar(name: contact.name, on: true), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(contact.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
              Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('bağlı', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
              ]),
            ])),
            IconButton(
              tooltip: 'Seçenekler',
              icon: const Icon(Icons.more_vert, color: KnkColors.textDim, size: 20),
              onPressed: () => _showMenu(context),
            ),
          ]),
        ),
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
      _Avatar(name: contact.name, on: false), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: KnkColors.text)),
        const Text('davet gönderildi · onay bekleniyor', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
      ])),
    ]),
  );
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool on;
  const _Avatar({required this.name, required this.on});
  @override
  Widget build(BuildContext context) {
    // characters: emoji / birleşik harfler ortadan bölünmesin.
    final trimmed = name.trim();
    final initials = trimmed.isEmpty ? '?' : trimmed.characters.take(2).toString().toUpperCase();
    return Container(
      width: 38, height: 38, alignment: Alignment.center,
      decoration: BoxDecoration(color: KnkColors.line, borderRadius: BorderRadius.circular(8), border: on ? Border.all(color: KnkColors.accent.withOpacity(0.5)) : null),
      child: Text(initials, style: TextStyle(color: on ? KnkColors.accent : KnkColors.textDim, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
