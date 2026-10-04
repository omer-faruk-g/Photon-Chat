import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../photon_api.dart';
import '../theme.dart';
import '../app_keys.dart';
import '../i18n.dart';
import 'add_contact_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'group_chat_screen.dart';
import 'stories_screen.dart';
import 'pulse_ai_screen.dart';
import '../story_manager.dart';
import '../vip.dart';
import '../vip_text.dart';
import 'profile_screen.dart';
import 'shop_screen.dart';

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
  String _myAvatar = '';
  String _myStatusMsg = '';
  final Map<String, int> _groupPendingCounts = {};
  final Map<String, bool> _online = {};
  List<StoryItem> _stories = [];
  VipStatus _myVip = VipStatus.none;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    final savedContacts = await LocalStore.loadContacts();
    final savedGroups = await LocalStore.loadGroups();
    final blockList = await LocalStore.loadBlockList();
    final statusMsg = await LocalStore.loadStatusMsg();
    final avatar = await LocalStore.loadAvatar();
    if (!mounted) return;
    setState(() {
      _contacts = savedContacts;
      _groups = savedGroups;
      _blockList = blockList;
      _loading = false;
      _myAvatar = avatar ?? '';
      _myStatusMsg = statusMsg ?? '';
    });
    StoryManager.loadStories().then((s) { if (mounted) setState(() => _stories = s); });
    _loadMyVip();
    await PhotonApi.registerPresence(widget.myServerUrl, widget.identity.fipId, widget.identity.code, widget.displayName, statusMsg: statusMsg ?? '', avatar: avatar ?? '');
    _sync();
    _groupSync();
    _presenceLoop();
  }

  Future<void> _loadMyVip() async {
    final raw = await PhotonApi.getTier(widget.identity.fipId);
    if (mounted && raw != null) setState(() => _myVip = VipStatus.fromJson(raw));
  }

  Future<void> _presenceLoop() async {
    // Re-register presence periodically so a server cold-start (Render free
    // tier sleeps after 15 min idle) doesn't leave you looking offline to your
    // contacts once the server wakes up with an empty users map.
    while (mounted) {
      await Future.delayed(const Duration(seconds: 45));
      if (!mounted) return;
      try {
        final avatar = await LocalStore.loadAvatar();
        final statusMsg = await LocalStore.loadStatusMsg();
        await PhotonApi.registerPresence(widget.myServerUrl, widget.identity.fipId,
            widget.identity.code, widget.displayName,
            statusMsg: statusMsg, avatar: avatar);
      } catch (_) {}
    }
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _toast = null); });
  }

  Future<void> _sync() async {
    final me = widget.identity;
    final incoming = await PhotonApi.getIncomingRequests(widget.myServerUrl, me.fipId);
    for (final req in incoming) {
      final fromFipId = req['fromFipId'] as String;
      if (_blockList.contains(fromFipId)) continue;
      final fromServerUrl = (req['fromServerUrl'] as String?) ?? '';
      if (!_contacts.any((c) => c.fipId == fromFipId)) {
        _contacts.add(Contact(fipId: fromFipId, name: (req['fromName'] as String?) ?? AppLang.instance.t('unknown'),
            code: (req['fromCode'] as String?) ?? '?????', serverUrl: fromServerUrl, status: 'pending_in'));
      }
    }
    final accepted = await PhotonApi.getAcceptedRequests(widget.myServerUrl, me.fipId);
    for (final fipId in accepted) {
      final idx = _contacts.indexWhere((c) => c.fipId == fipId);
      if (idx != -1 && _contacts[idx].status == 'pending_out') _contacts[idx].status = 'on';
    }
    for (final c in _contacts.where((c) => c.status == 'on').toList()) {
      // Contact's presence lookup may miss if their server is cold-starting
      // (Render free tier sleeps after 15 min). One miss must NOT delete the
      // contact — mark them offline, retry next sync. Only give up if the
      // contact's user record itself is gone (profile fetch succeeds and
      // returns null status? — we treat this as still-present for safety).
      final active = await PhotonApi.isActive(c.serverUrl, c.fipId);
      _online[c.fipId] = active;
      if (active) {
        final profile = await PhotonApi.getProfile(c.serverUrl, c.fipId);
        if (profile != null) {
          // The name is refreshed like any other profile field. It used to be
          // frozen at the moment the contact was added, which is why an alias
          // switch could never reach people who already had you.
          final freshName = (profile['name'] as String?) ?? '';
          if (freshName.isNotEmpty) c.name = freshName;
          c.avatar = (profile['avatar'] as String?) ?? '';
          c.statusMsg = (profile['statusMsg'] as String?) ?? '';
          c.lastSeen = (profile['lastSeen'] as int?) ?? 0;
          c.bio = (profile['bio'] as String?) ?? '';
        }
      }
    }
    await LocalStore.saveContacts(_contacts);
    // Our own id is included so screens further down (stories, groups) can read
    // the tier straight from the cache instead of each making its own request.
    await VipCache.instance
        .refresh(bridgeUrl, [..._contacts.map((c) => c.fipId), me.fipId]);
    if (mounted) setState(() {});
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) _sync();
  }

  Future<void> _groupSync() async {
    for (final g in _groups.where((g) => g.isOwner)) {
      try {
        // Re-register the group's code on the bridge each cycle so members
        // can join by code alone (bridge is in-memory; survives via snapshot).
        PhotonApi.registerOnBridge(g.groupCode, widget.myServerUrl, actor: widget.identity.fipId);
        final reqs = await PhotonApi.getGroupJoinRequests(widget.myServerUrl, g.groupId);
        if (mounted) setState(() => _groupPendingCounts[g.groupId] = reqs.length);
      } catch (_) {}
    }
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) _groupSync();
  }

  Future<void> _accept(Contact c) async {
    if (!mounted) return;
    setState(() => c.status = 'on');
    await LocalStore.saveContacts(_contacts);
    await PhotonApi.acceptFriendRequest(myServerUrl: widget.myServerUrl, myFipId: widget.identity.fipId, otherFipId: c.fipId);
    _showToast('${c.name} ${AppLang.instance.t('friendAddedSuffix')}');
  }

  Future<void> _decline(Contact c) async {
    setState(() => _contacts.removeWhere((x) => x.fipId == c.fipId));
    await LocalStore.saveContacts(_contacts);
  }

  Future<void> _blockContact(Contact c) async {
    await LocalStore.blockUser(c.fipId);
    if (!mounted) return;
    setState(() {
      _blockList.add(c.fipId);
      _contacts.removeWhere((x) => x.fipId == c.fipId);
    });
    await LocalStore.saveContacts(_contacts);
    _showToast('${c.name} ${AppLang.instance.t('blockedSuffix')}');
  }

  Future<void> _openAddScreen() async {
    final result = await Navigator.push<Contact>(context, MaterialPageRoute(
      builder: (_) => AddContactScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (result != null) {
      setState(() => _contacts.add(result));
      await LocalStore.saveContacts(_contacts);
      _showToast('${result.name} ${AppLang.instance.t('inviteSentSuffix')}');
    }
  }

  Future<void> _openCreateGroup() async {
    final result = await Navigator.push<Group>(context, MaterialPageRoute(
      builder: (_) => CreateGroupScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (result != null) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('${AppLang.instance.t('groupCreatedPrefix')}: ${result.name}');
    }
  }

  Future<void> _openJoinGroup() async {
    final result = await Navigator.push<Group>(context, MaterialPageRoute(
      builder: (_) => JoinGroupScreen(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl),
    ));
    if (result != null) {
      setState(() => _groups.add(result));
      await LocalStore.saveGroups(_groups);
      _showToast('${result.name} ${AppLang.instance.t('joinRequestSentSuffix')}');
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

  /// Your own profile. Opened from your avatar rather than jumping straight to
  /// Settings, because your intro animation has to play for you as well.
  Future<void> _openMyProfile() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ProfileScreen(
        fipId: widget.identity.fipId,
        name: widget.displayName,
        code: widget.identity.code,
        avatar: _myAvatar,
        isOnline: true,
        isSelf: true,
        onSettings: () { Navigator.pop(context); _openSettings(); },
      ),
    ));
    if (mounted) _loadMyVip();
  }

  void _openContactProfile(Contact c) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ProfileScreen(
        fipId: c.fipId,
        name: c.name,
        code: c.code,
        avatar: c.avatar,
        bio: c.bio,
        statusMsg: c.statusMsg,
        isOnline: _online[c.fipId] ?? false,
        onMessage: () { Navigator.pop(context); _openChat(c); },
      ),
    ));
  }

  Future<void> _openShop() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ShopScreen(fipId: widget.identity.fipId),
    ));
    if (mounted) _loadMyVip();
  }

  void _openPulseAI() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PulseAiScreen(myServerUrl: widget.myServerUrl)));
  }

  void _createStory() {
    final ctrl = TextEditingController();
    final colors = [0xFF1A1A2E, 0xFF16213E, 0xFF0F3460, 0xFF533483, 0xFFE94560, 0xFF2B2D42];
    int selectedColor = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        backgroundColor: PhotonColors.panel,
        title: Text(AppLang.instance.t('createStory'), style: TextStyle(color: PhotonColors.text, fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl, autofocus: true, maxLines: 3, maxLength: 200,
            style: TextStyle(color: PhotonColors.text),
            decoration: InputDecoration(hintText: AppLang.instance.t('whatAreYouThinking'), hintStyle: TextStyle(color: PhotonColors.textDim), filled: true, fillColor: PhotonColors.bg, border: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line))),
          ),
          const SizedBox(height: 16),
          Text(AppLang.instance.t('backgroundColor'), style: PText.meta),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(colors.length, (i) => GestureDetector(
            onTap: () => ss(() => selectedColor = i),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: Color(colors[i]).withAlpha(255), shape: BoxShape.circle, border: Border.all(color: selectedColor == i ? PhotonColors.accent : Colors.transparent, width: 2)),
            ),
          ))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLang.instance.t('cancel'), style: TextStyle(color: PhotonColors.textDim))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (ctrl.text.trim().isEmpty) return;
              await StoryManager.postStory(serverUrl: widget.myServerUrl, fipId: widget.identity.fipId, authorName: widget.displayName, type: 'text', content: ctrl.text.trim());
              final stories = await StoryManager.loadStories();
              if (mounted) setState(() => _stories = stories);
            },
            child: Text(AppLang.instance.t('share'), style: TextStyle(color: PhotonColors.accent)),
          ),
        ],
      )),
    ).then((_) => ctrl.dispose());
  }

  void _openSettings() async {
    final deactivated = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SettingsScreen(identity: widget.identity, myServerUrl: widget.myServerUrl, displayName: widget.displayName)));
    if (deactivated == true && mounted) {
      (rootGateKey.currentState as dynamic)?.reload();
      Navigator.popUntil(context, (route) => route.isFirst);
    }
    // Ayarlardan dönerken avatar/statusMsg güncellenmiş olabilir
    final avatar = await LocalStore.loadAvatar();
    final statusMsg = await LocalStore.loadStatusMsg();
    if (mounted) setState(() { _myAvatar = avatar ?? ''; _myStatusMsg = statusMsg ?? ''; });
  }

  Future<void> _handleExit(List<Contact> active) async {
    if (active.isEmpty) { SystemNavigator.pop(); return; }
    final keep = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PhotonColors.panel,
        title: Text(AppLang.instance.t('keepChatsQuestion'), style: TextStyle(color: PhotonColors.text, fontSize: 15)),
        content: Text(AppLang.instance.t('deactivateWarn'), style: PText.small),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLang.instance.t('noDestroy'), style: TextStyle(color: PhotonColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLang.instance.t('yesKeep'), style: TextStyle(color: PhotonColors.accent))),
        ],
      ),
    );
    if (keep == false) {
      for (final c in active) await PhotonApi.deleteChat(widget.myServerUrl, chatKeyFor(widget.identity.fipId, c.fipId), actor: widget.identity.fipId);
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(body: Center(child: CircularProgressIndicator(color: PhotonColors.accent)));
    final incoming = _contacts.where((c) => c.status == 'pending_in').toList();
    final outgoing = _contacts.where((c) => c.status == 'pending_out').toList();
    final active = _contacts.where((c) => c.status == 'on').toList();

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async { if (!didPop) await _handleExit(active); },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: Space.s2,
          title: Row(children: [
            BrandMark(size: 28),
            const SizedBox(width: Space.s1),
            Text('Photon Chat', style: PText.h2), // brand name — not translated
          ]),
          actions: [
            // Pulse AI lost its card on the home screen; this keeps it one tap away.
            IconButton(
              icon: Icon(Icons.bolt_outlined, color: PhotonColors.accent),
              tooltip: AppLang.instance.t('pulseAiTitle'),
              onPressed: _openPulseAI,
            ),
            // Own avatar doubles as the settings entry point.
            Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: GestureDetector(
                onTap: _openMyProfile,
                // Our own avatar follows the alias too: switching to one and
                // still seeing your real initials in the app bar contradicts
                // "the alias replaces your name everywhere".
                child: _AvatarWidget(
                    name: vipDisplayName(_myVip, widget.displayName),
                    avatar: _myAvatar,
                    size: 32,
                    on: true),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(Space.s2, Space.s2, Space.s2, Space.s7 + MediaQuery.of(context).padding.bottom),
              children: [
                // Own code, right-aligned under the avatar. Replaces the old
                // full-height profile card.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Shop sits beside the chip rather than inside it, so a
                    // subscriber-less account still has a way in.
                    Tooltip(
                      message: AppLang.instance.t('shopTitle'),
                      child: HoverCard(
                        onTap: _openShop,
                        color: PhotonColors.accentWash,
                        padding: const EdgeInsets.all(Space.s1),
                        child: Icon(Icons.storefront_outlined, size: 18, color: PhotonColors.accent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    HoverCard(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.identity.code));
                        _showToast('${AppLang.instance.t('codeCopiedPrefix')}: ${widget.identity.code}');
                      },
                      color: PhotonColors.accentWash,
                      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('${AppLang.instance.t('kodum')}  ', style: PText.label),
                          Text(widget.identity.code, style: PText.title.merge(PText.tabular).copyWith(color: PhotonColors.accent, letterSpacing: 3)),
                          const SizedBox(width: Space.s1),
                          Icon(Icons.copy_outlined, size: 14, color: PhotonColors.accent),
                          // Tier rides in the same chip, in the colour the
                          // subscriber picked. Absent entirely when unsubscribed.
                          if (_myVip.effectiveTier != VipTier.none) ...[
                            Text('  ·  ', style: PText.meta),
                            Text(
                              _myVip.effectiveTier.label,
                              style: TextStyle(
                                color: vipNameColor(_myVip) ?? PhotonColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ]),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s2),

                StoriesRow(identity: widget.identity, displayName: widget.displayName, myServerUrl: widget.myServerUrl, contacts: _contacts),
                const SizedBox(height: Space.s3),

                // Invites still get their own block — they need a decision, so
                // they must not blend into the list below.
                if (incoming.isNotEmpty) ...[
                  _SectionTitle(AppLang.instance.t('invites'), count: incoming.length),
                  ...incoming.map((c) => _RequestRow(contact: c, onAccept: () => _accept(c), onDecline: () => _decline(c))),
                  const SizedBox(height: 16),
                ],

                // One unified list: contacts and groups, no section headers.
                if (active.isEmpty && outgoing.isEmpty && incoming.isEmpty && _groups.isEmpty)
                  _EmptyState(onAdd: _openAddScreen),
                ...active.map((c) => _ContactRow(
                  contact: c,
                  vip: VipCache.instance.peek(c.fipId),
                  isOnline: _online[c.fipId] ?? false,
                  onTap: () => _openChat(c),
                  onBlock: () => _blockContact(c),
                  onAvatarTap: () => _openContactProfile(c),
                )),
                ..._groups.map((g) => _GroupRow(group: g, pendingCount: _groupPendingCounts[g.groupId] ?? 0, onTap: () => _openGroupChat(g))),
                ...outgoing.map((c) => _PendingOutRow(contact: c)),
              ],
            ),

            // Alt bar: iki düğme — extra margin so Android gesture bar / 3-button nav doesn't overlap
            Positioned(
              left: Space.s2, right: Space.s2,
              bottom: Space.s4 + MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewPadding.bottom,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openAddScreen,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(AppLang.instance.t('addContact')),
                    ),
                  ),
                  const SizedBox(width: Space.s1),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: photonGhostButtonStyle().copyWith(backgroundColor: WidgetStateProperty.resolveWith((s) =>
                          s.contains(WidgetState.hovered) ? PhotonColors.accentWash : PhotonColors.panel)),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        builder: (_) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: Icon(Icons.group_add_outlined, color: PhotonColors.accent),
                                title: Text(AppLang.instance.t('createGroup'), style: TextStyle(color: PhotonColors.text)),
                                onTap: () { Navigator.pop(context); _openCreateGroup(); },
                              ),
                              ListTile(
                                leading: Icon(Icons.login_outlined, color: PhotonColors.accent),
                                title: Text(AppLang.instance.t('joinGroup'), style: TextStyle(color: PhotonColors.text)),
                                onTap: () { Navigator.pop(context); _openJoinGroup(); },
                              ),
                            ],
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.group_outlined, size: 18),
                      label: Text(AppLang.instance.t('groups')),
                    ),
                  ),
                ],
              ),
            ),

            if (_toast != null)
              Positioned(
                left: Space.s2, right: Space.s2, bottom: Space.s4 + Space.s6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: PhotonColors.panelAlt, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(8)),
                  child: Text(_toast!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: PhotonColors.text)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Yardımcı Widget'lar ────────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1 + 4),
      // Same shape as a contact row — icon trailing — so the merged list reads
      // as one column instead of two visually different kinds of row.
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.name, style: PText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${AppLang.instance.t(group.isOwner ? 'roleOwner' : 'roleMember')} · ${AppLang.instance.t('codeLabel')}: ${group.groupCode}',
              style: PText.meta),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(group.description, style: PText.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ])),
        if (pendingCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: PhotonColors.accent2, borderRadius: BorderRadius.circular(16)),
            child: Text('$pendingCount', style: TextStyle(color: PhotonTheme.instance.isDark ? const Color(0xFF2A1700) : Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ],
        Container(width: Space.s5, height: Space.s5, alignment: Alignment.center,
            decoration: BoxDecoration(color: PhotonColors.accentWash, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(Space.s5 / 4)),
            child: Icon(Icons.group_outlined, color: PhotonColors.accent, size: 22)),
      ]),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final int? count;
  const _SectionTitle(this.text, {this.count});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Row(
      children: [
        Text(trUpper(text), style: PText.label),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(color: PhotonColors.line, borderRadius: BorderRadius.circular(8)),
            child: Text('$count', style: TextStyle(color: PhotonColors.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s3),
    decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.person_add_outlined, color: PhotonColors.accent2, size: 28),
      const SizedBox(height: Space.s2),
      Text(AppLang.instance.t('emptyContacts'), style: PText.h2),
      const SizedBox(height: Space.s1),
      Text(AppLang.instance.t('emptyContactsHint'), style: PText.small),
      const SizedBox(height: Space.s3),
      OutlinedButton(onPressed: onAdd, child: Text(AppLang.instance.t('addContact'))),
    ]),
  );
}

class _RequestRow extends StatelessWidget {
  final Contact contact;
  final VoidCallback onAccept, onDecline;
  const _RequestRow({required this.contact, required this.onAccept, required this.onDecline});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s1),
    padding: const EdgeInsets.all(Space.s2),
    decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.accent2), borderRadius: BorderRadius.circular(PhotonRadius.card)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _AvatarWidget(name: contact.name, avatar: contact.avatar, size: Space.s5, on: false),
        const SizedBox(width: Space.s2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(contact.name, style: PText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${AppLang.instance.t('codeLabel')}: ${contact.code}', style: PText.small.merge(PText.tabular)),
        ])),
      ]),
      const SizedBox(height: Space.s2),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: onDecline, child: Text(AppLang.instance.t('delete')))),
        const SizedBox(width: Space.s1),
        Expanded(child: ElevatedButton(onPressed: onAccept, child: Text(AppLang.instance.t('accept')))),
      ]),
    ]),
  );
}

class _ContactRow extends StatelessWidget {
  final Contact contact;
  /// Null while the bridge lookup is still pending or unreachable — the row
  /// then renders exactly as it did before paid tiers existed.
  final VipStatus? vip;
  final bool isOnline;
  final VoidCallback onTap;
  final VoidCallback onBlock;

  /// Tapping the avatar opens the profile; tapping anywhere else opens the
  /// chat, which is what the row did before profiles existed.
  final VoidCallback onAvatarTap;
  const _ContactRow({required this.contact, required this.vip, required this.isOnline, required this.onTap, required this.onBlock, required this.onAvatarTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () {
      showModalBottomSheet(
        context: context,
        backgroundColor: PhotonColors.panel,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (contact.bio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: PhotonColors.bg,
                      border: Border.all(color: PhotonColors.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(AppLang.instance.t('bioSection'), style: PText.label),
                      const SizedBox(height: 4),
                      Text(contact.bio, style: TextStyle(color: PhotonColors.text, fontSize: 13, height: 1.5)),
                    ]),
                  ),
                ),
              ListTile(
                leading: Icon(Icons.block_outlined, color: PhotonColors.danger),
                title: Text('${contact.name} — ${AppLang.instance.t('blockUser')}', style: TextStyle(color: PhotonColors.danger)),
                onTap: () { Navigator.pop(context); onBlock(); },
              ),
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: PhotonColors.textDim),
                title: Text(AppLang.instance.t('giveUp'), style: TextStyle(color: PhotonColors.textDim)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    },
    child: Padding(
      padding: const EdgeInsets.only(bottom: Space.s1),
      child: HoverCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1 + 4),
        // Avatar sits on the trailing edge so the names line up flush left and
        // the row reads as a single label, per the agreed layout.
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(
                  vipDisplayName(vip, contact.name),
                  style: PText.title.copyWith(color: vipNameColor(vip) ?? PhotonColors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if ((vip ?? VipStatus.none).effectiveTier.premiumTag) ...[
                const SizedBox(width: 8),
                VipBadge(status: vip),
              ],
            ]),
            const SizedBox(height: 2),
            Text(
              isOnline ? AppLang.instance.t('online') : (contact.statusMsg.isNotEmpty ? contact.statusMsg : AppLang.instance.t('offline')),
              style: PText.small.copyWith(color: isOnline ? PhotonColors.accent : PhotonColors.textDim),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ])),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(children: [
            _AvatarWidget(name: vipDisplayName(vip, contact.name), avatar: contact.avatar, size: Space.s5, on: true),
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: isOnline ? PhotonColors.accent : PhotonColors.textDim,
                  shape: BoxShape.circle,
                  border: Border.all(color: PhotonColors.panel, width: 2),
                ),
              ),
            ),
          ]),
          ),
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
    margin: const EdgeInsets.only(bottom: Space.s1),
    padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1 + 4),
    decoration: BoxDecoration(color: PhotonColors.bg, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
    child: Row(children: [
      _AvatarWidget(name: contact.name, avatar: contact.avatar, size: Space.s5, on: false),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(contact.name, style: PText.title.copyWith(color: PhotonColors.textDim)),
        const SizedBox(height: 2),
        Row(children: [
          Icon(Icons.schedule_outlined, size: 14, color: PhotonColors.textDim),
          const SizedBox(width: 4),
          Text(AppLang.instance.t('invitePendingApproval'), style: PText.meta),
        ]),
      ])),
    ]),
  );
}

// ─── Avatar Widget ──────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  final String name;
  final bool on;
  final String avatar;
  final double size;
  const _AvatarWidget({required this.name, required this.on, this.avatar = '', this.size = 46});
  @override
  Widget build(BuildContext context) {
    if (avatar.isNotEmpty) {
      try {
        final bytes = base64Decode(avatar);
        return Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: on ? Border.all(color: PhotonColors.accent.withOpacity(0.5), width: 2) : null,
            image: DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
        );
      } catch (_) {}
    }
    final initials = name.trim().isEmpty ? '?' : trUpper(name.trim().substring(0, name.trim().length >= 2 ? 2 : 1));
    return Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? PhotonColors.accentWash : PhotonColors.panelAlt,
        borderRadius: BorderRadius.circular(size / 4),
        border: on ? Border.all(color: PhotonColors.accent.withOpacity(0.5)) : null,
      ),
      child: Text(initials, style: TextStyle(fontFamily: PhotonFonts.display, color: on ? PhotonColors.accent : PhotonColors.textDim, fontSize: size * 0.36)),
    );
  }
}
