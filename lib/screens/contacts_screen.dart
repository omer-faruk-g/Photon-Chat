import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  Map<String, String> _verifiedKeys = {};

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
    final verified = await LocalStore.loadVerifiedKeys();
    if (_disposed) return;
    setState(() { _contacts = savedContacts; _groups = savedGroups; _blockList = blockList; _verifiedKeys = verified; _loading = false; });
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
    // Sohbette kişinin public key'i öğrenilmiş veya doğrulanmış olabilir.
    await _saveContacts();
    final verified = await LocalStore.loadVerifiedKeys();
    if (!_disposed) setState(() => _verifiedKeys = verified);
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
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final incoming = _contacts.where((c) => c.status == 'pending_in').toList();
    final outgoing = _contacts.where((c) => c.status == 'pending_out').toList();
    final active = _contacts.where((c) => c.status == 'on').toList();

    return PopScope(
      // Tarayıcıda "uygulamadan çıkma" yoktur; çıkış sorusu sadece mobil/masaüstünde sorulur.
      canPop: kIsWeb,
      onPopInvokedWithResult: (didPop, _) async { if (!didPop && !kIsWeb) await _handleExit(active); },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: Space.s6,
          leading: const Padding(padding: EdgeInsets.only(left: Space.s2), child: Center(child: BrandMark(size: 32))),
          title: const Text('Photon Chat'),
          actions: [
            IconButton(tooltip: 'Ayarlar', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
            const SizedBox(width: Space.s1),
          ],
        ),
        // Ana eylem listenin üstünde yüzmez; altta kendi şeridinde durur.
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(color: KnkColors.bg, border: Border(top: BorderSide(color: KnkColors.line))),
          child: SafeArea(
            top: false,
            child: ContentWidth(
              shrinkHeight: true,
              child: Padding(
                padding: const EdgeInsets.all(Space.s2),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(Space.s5)),
                  onPressed: _openAddScreen,
                  icon: const Icon(Icons.person_add_alt_outlined, size: 20),
                  label: const Text('Kişi ekle'),
                ),
              ),
            ),
          ),
        ),
        body: ContentWidth(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(Space.s2, Space.s3, Space.s2, Space.s5),
                children: [
                  _MyCodeCard(code: widget.identity.code, onCopy: () async {
                    await Clipboard.setData(ClipboardData(text: widget.identity.code));
                    _showToast('Kodun kopyalandı: ${widget.identity.code}');
                  }),
                  const SizedBox(height: Space.s2),
                  _PulseAiCard(onTap: _openPulseAI),
                  if (incoming.isNotEmpty) ...[
                    const SizedBox(height: Space.s5),
                    SectionLabel('Davetler · ${incoming.length}'),
                    ...incoming.map((c) => _RequestRow(contact: c, onAccept: () => _accept(c), onDecline: () => _decline(c))),
                  ],
                  const SizedBox(height: Space.s5),
                  SectionLabel('Kişiler · ${active.length}'),
                  if (active.isEmpty && outgoing.isEmpty && incoming.isEmpty) _EmptyState(onAdd: _openAddScreen),
                  ...active.map((c) => _ContactRow(
                    contact: c,
                    onTap: () => _openChat(c),
                    onBlock: () => _blockContact(c),
                    trust: keyTrust(_verifiedKeys, c.fipId, c.publicKey),
                  )),
                  ...outgoing.map((c) => _PendingOutRow(contact: c)),
                  const SizedBox(height: Space.s5),
                  SectionLabel(
                    'Gruplar · ${_groups.length}',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton.icon(onPressed: _openCreateGroup, icon: const Icon(Icons.add, size: 18), label: const Text('Oluştur')),
                      TextButton.icon(onPressed: _openJoinGroup, icon: const Icon(Icons.login, size: 18), label: const Text('Katıl')),
                    ]),
                  ),
                  if (_groups.isEmpty)
                    const _Hint(icon: Icons.groups_outlined, text: 'Henüz bir grubun yok. Bir grup oluştur ya da sana verilen grup adresiyle katıl.'),
                  ..._groups.map((g) => _GroupRow(group: g, pendingCount: _groupPendingCounts[g.groupId] ?? 0, onTap: () => _openGroupChat(g))),
                ],
              ),
              if (_toast != null)
                Positioned(
                  left: Space.s2, right: Space.s2, bottom: Space.s2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
                    decoration: BoxDecoration(color: KnkColors.panelAlt, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(KnkRadius.card), boxShadow: knkShadow()),
                    child: Text(_toast!, textAlign: TextAlign.center, style: KnkText.small.copyWith(color: KnkColors.text)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kendi eşleşme kodun: ekranın en önemli bilgisi, sitedeki kod satırıyla aynı tasarım.
class _MyCodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;
  const _MyCodeCard({required this.code, required this.onCopy});
  @override
  Widget build(BuildContext context) => HoverCard(
    onTap: onCopy,
    color: KnkColors.accentWash,
    padding: const EdgeInsets.all(Space.s3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SENİN KODUN', style: KnkText.label),
        SizedBox(height: Space.s1),
        Text('Arkadaşın seni bu 5 haneyle ekler. Kopyalamak için dokun.', style: KnkText.small),
      ])),
      const SizedBox(width: Space.s2),
      Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(code, style: KnkText.code.copyWith(fontSize: 34, letterSpacing: 6)))),
      const SizedBox(width: Space.s1),
      const Padding(padding: EdgeInsets.only(bottom: Space.s1), child: Icon(Icons.content_copy_outlined, size: 18, color: KnkColors.accent)),
    ]),
  );
}

class _PulseAiCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PulseAiCard({required this.onTap});
  @override
  Widget build(BuildContext context) => HoverCard(
    onTap: onTap,
    child: const Row(
      children: [
        _IconTile(icon: Icons.bolt_outlined),
        SizedBox(width: Space.s2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pulse AI', style: KnkText.strong),
          Text('Yapay zeka asistanın. Bir kelimenin anlamını ya da aklındaki soruyu sor.', style: KnkText.small),
        ])),
        Icon(Icons.chevron_right, color: KnkColors.textDim),
      ],
    ),
  );
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  const _IconTile({required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    width: KnkSize.tile, height: KnkSize.tile, alignment: Alignment.center,
    decoration: BoxDecoration(color: KnkColors.accentWash, borderRadius: BorderRadius.circular(KnkRadius.card), border: Border.all(color: KnkColors.line)),
    child: Icon(icon, color: KnkColors.accent, size: 20),
  );
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s2),
    decoration: BoxDecoration(border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(KnkRadius.card)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: KnkColors.textDim, size: 20),
      const SizedBox(width: Space.s2),
      Expanded(child: Text(text, style: KnkText.small)),
    ]),
  );
}

class _GroupRow extends StatelessWidget {
  final Group group;
  final int pendingCount;
  final VoidCallback onTap;
  const _GroupRow({required this.group, required this.pendingCount, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s1),
    child: HoverCard(
      onTap: onTap,
      child: Row(children: [
        const _IconTile(icon: Icons.groups_outlined),
        const SizedBox(width: Space.s2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.name, overflow: TextOverflow.ellipsis, style: KnkText.strong),
          Text('${group.isOwner ? 'Kurucu' : 'Üye'} · ${group.groupCode}', style: KnkText.small.merge(KnkText.tabular)),
        ])),
        if (pendingCount > 0)
          Tooltip(
            message: '$pendingCount katılma isteği',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.s1),
              constraints: const BoxConstraints(minWidth: Space.s3),
              height: Space.s3,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: KnkColors.accent2, borderRadius: BorderRadius.circular(KnkRadius.pill)),
              child: Text('$pendingCount', style: const TextStyle(color: KnkColors.onAccent, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        const SizedBox(width: Space.s1),
        const Icon(Icons.chevron_right, color: KnkColors.textDim),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s3),
    decoration: BoxDecoration(border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(KnkRadius.card)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.person_add_alt_outlined, color: KnkColors.accent2, size: 28),
      const SizedBox(height: Space.s2),
      const Text('Rehberin henüz boş.', style: KnkText.h3),
      const SizedBox(height: Space.s1),
      const Text('Arkadaşından 5 haneli kodunu iste ve buraya yaz. O kabul edince sohbet açılır.', style: KnkText.small),
      const SizedBox(height: Space.s2),
      OutlinedButton(onPressed: onAdd, child: const Text('Kod ile ekle')),
    ]),
  );
}

class _RequestRow extends StatelessWidget {
  final Contact contact;
  final VoidCallback onAccept, onDecline;
  const _RequestRow({required this.contact, required this.onAccept, required this.onDecline});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s1),
    child: HoverCard(
      borderColor: KnkColors.accent2.withOpacity(0.5),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.s2,
        runSpacing: Space.s2,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _Avatar(name: contact.name, on: false), const SizedBox(width: Space.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(contact.name, overflow: TextOverflow.ellipsis, style: KnkText.strong),
                Text('kod ${contact.code} · seni eklemek istiyor', style: KnkText.small.merge(KnkText.tabular)),
              ]),
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(onPressed: onDecline, child: const Text('Reddet')),
            const SizedBox(width: Space.s1),
            ElevatedButton(onPressed: onAccept, child: const Text('Kabul et')),
          ]),
        ],
      ),
    ),
  );
}

class _ContactRow extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onBlock;
  final KeyTrust trust;
  const _ContactRow({required this.contact, required this.onTap, required this.onBlock, this.trust = KeyTrust.none});

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s1),
    child: HoverCard(
      onTap: onTap,
      onLongPress: () => _showMenu(context),
      onSecondaryTap: () => _showMenu(context),
      padding: const EdgeInsets.fromLTRB(Space.s2, Space.s2, Space.s1, Space.s2),
      child: Row(children: [
        _Avatar(name: contact.name, on: true), const SizedBox(width: Space.s2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(contact.name, overflow: TextOverflow.ellipsis, style: KnkText.strong),
          Row(children: [
            switch (trust) {
              KeyTrust.verified => const Icon(Icons.verified_user_outlined, color: KnkColors.accent, size: 14),
              KeyTrust.changed => const Icon(Icons.gpp_bad_outlined, color: KnkColors.danger, size: 14),
              _ => const Icon(Icons.lock_outline, color: KnkColors.textDim, size: 14),
            },
            const SizedBox(width: Space.s1),
            Flexible(child: Text(
              switch (trust) {
                KeyTrust.verified => 'şifreli · doğrulandı',
                KeyTrust.changed => 'anahtar değişti, yeniden doğrula',
                _ => 'şifreli · doğrulanmadı',
              },
              overflow: TextOverflow.ellipsis,
              style: KnkText.small.copyWith(color: switch (trust) {
                KeyTrust.verified => KnkColors.accent,
                KeyTrust.changed => KnkColors.danger,
                _ => KnkColors.textDim,
              }),
            )),
          ]),
        ])),
        IconButton(
          tooltip: 'Seçenekler',
          icon: const Icon(Icons.more_vert, color: KnkColors.textDim, size: 20),
          onPressed: () => _showMenu(context),
        ),
      ]),
    ),
  );
}

class _PendingOutRow extends StatelessWidget {
  final Contact contact;
  const _PendingOutRow({required this.contact});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s1),
    child: HoverCard(
      child: Row(children: [
        _Avatar(name: contact.name, on: false), const SizedBox(width: Space.s2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(contact.name, overflow: TextOverflow.ellipsis, style: KnkText.strong),
          Row(children: [
            const Icon(Icons.schedule, color: KnkColors.accent2, size: 14),
            const SizedBox(width: Space.s1),
            Text('davet gönderildi, onay bekleniyor', style: KnkText.small.copyWith(color: KnkColors.accent2)),
          ]),
        ])),
      ]),
    ),
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
      width: KnkSize.tile, height: KnkSize.tile, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? KnkColors.accentWash : KnkColors.panelAlt,
        borderRadius: BorderRadius.circular(KnkRadius.card),
        border: Border.all(color: on ? KnkColors.accent.withOpacity(0.5) : KnkColors.line),
      ),
      child: Text(initials, style: TextStyle(fontFamily: KnkFonts.display, color: on ? KnkColors.accent : KnkColors.textDim, fontSize: 15)),
    );
  }
}
