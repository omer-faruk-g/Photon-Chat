import 'package:flutter/material.dart';
import '../device_manager.dart';
import '../photon_api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../fip.dart';

class DevicesScreen extends StatefulWidget {
  final FipBlock identity;
  final String myServerUrl;
  const DevicesScreen({super.key, required this.identity, required this.myServerUrl});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<LinkedDevice> _devices = [];
  List<DeviceLinkRequest> _pendingRequests = [];
  bool _loading = true;
  String? _activeCode;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final devices = await DeviceManager.loadLinkedDevices();
    final reqMaps = await PhotonApi.getDeviceLinkRequests(widget.myServerUrl, widget.identity.fipId);
    final reqs = reqMaps.map((m) => DeviceLinkRequest.fromJson(m)).toList();
    if (mounted) setState(() { _devices = devices; _pendingRequests = reqs; _loading = false; });
  }

  List<LinkedDevice> get _linkedDevices => _devices.where((d) => !d.isFake && !d.isBanned).toList();
  List<LinkedDevice> get _fakeDevices => _devices.where((d) => d.isFake && !d.isBanned).toList();
  List<LinkedDevice> get _bannedDevices => _devices.where((d) => d.isBanned).toList();

  Future<void> _approveRequest(DeviceLinkRequest req) async {
    final attempt = int.tryParse(req.code) ?? 1;
    int codeLength;
    switch (attempt) {
      case 2: codeLength = 12; break;
      case 3: codeLength = 15; break;
      default: codeLength = 9;
    }
    final code = DeviceManager.generateCodeWithLength(codeLength);
    await PhotonApi.respondDeviceLink(widget.myServerUrl, widget.identity.fipId,
        requesterFipId: req.requesterFipId, status: 'code_sent', code: code);
    if (!mounted) return;
    setState(() => _activeCode = code);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PhotonColors.panel,
        title: Text('${AppLang.instance.t('verificationCodeAttempt')} (${AppLang.instance.t('attempt')} $attempt/3)', style: TextStyle(color: PhotonColors.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${AppLang.instance.t('enterCodeDigitsPrefix')} $codeLength ${AppLang.instance.t('enterCodeDigitsSuffix')}', style: PText.small),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: PhotonColors.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PhotonColors.accent, width: 2),
            ),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(code, style: TextStyle(color: PhotonColors.accent, fontSize: codeLength > 12 ? 20 : 28, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: PhotonFonts.body, fontFeatures: const [FontFeature.tabularFigures()]))),
          ),
          const SizedBox(height: 16),
          Text('${req.requesterName} ${AppLang.instance.t('tryingToConnectSuffix')}', style: PText.small),
          if (attempt > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_outlined, size: 14, color: PhotonColors.accent2),
                const SizedBox(width: 4),
                Flexible(child: Text('${AppLang.instance.t('attempt')} $attempt — ${attempt == 3 ? AppLang.instance.t('lastChance') : AppLang.instance.t('nextWillBe15')}', style: TextStyle(color: PhotonColors.accent2, fontSize: 11))),
              ]),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); _load(); },
            child: Text(AppLang.instance.t('ok'), style: TextStyle(color: PhotonColors.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectRequest(DeviceLinkRequest req) async {
    final device = LinkedDevice(
      deviceId: 'fake_${req.requesterFipId}_${DateTime.now().millisecondsSinceEpoch}',
      fipId: req.requesterFipId,
      name: '${req.requesterName} [FAKE]',
      linkedAt: DateTime.now().millisecondsSinceEpoch,
      isFake: true,
    );
    await DeviceManager.addLinkedDevice(device);
    await PhotonApi.respondDeviceLink(widget.myServerUrl, widget.identity.fipId,
        requesterFipId: req.requesterFipId, status: 'fake');
    await _load();
  }

  Future<void> _kickDevice(LinkedDevice device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PhotonColors.panel,
        title: Text(AppLang.instance.t('kickDevice'), style: TextStyle(color: PhotonColors.text)),
        content: Text(
          '${device.name} ${AppLang.instance.t('kickDeviceConfirmSuffix')}',
          style: PText.small,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLang.instance.t('cancel'), style: TextStyle(color: PhotonColors.textDim))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLang.instance.t('kickShort'), style: TextStyle(color: PhotonColors.danger))),
        ],
      ),
    );
    if (confirm != true) return;

    await DeviceManager.banDevice(device.deviceId);
    await DeviceManager.addBannedServer(widget.myServerUrl, device.fipId);
    await PhotonApi.banDeviceOnServer(widget.myServerUrl, widget.identity.fipId, device.fipId);
    await PhotonApi.kickDevice(widget.myServerUrl, widget.identity.fipId, device.deviceId);
    await _load();
  }

  Future<void> _banFake(LinkedDevice device) async {
    await DeviceManager.banDevice(device.deviceId);
    await DeviceManager.addBannedServer(widget.myServerUrl, device.fipId);
    await PhotonApi.banDeviceOnServer(widget.myServerUrl, widget.identity.fipId, device.fipId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} ${AppLang.instance.t('bannedSuffix')}'), backgroundColor: PhotonColors.danger));
    }
    await _load();
  }

  Future<void> _giveModToFake(LinkedDevice device) async {
    await DeviceManager.toggleMod(device.deviceId);
    await _load();
  }

  void _viewActivities(LinkedDevice device) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceActivityScreen(device: device, serverUrl: widget.myServerUrl, ownerFipId: widget.identity.fipId)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLang.instance.t('deviceManagement')),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: PhotonColors.accent,
          unselectedLabelColor: PhotonColors.textDim,
          indicatorColor: PhotonColors.accent,
          tabs: [
            Tab(text: '${AppLang.instance.t('devices')} (${_linkedDevices.length})'),
            Tab(text: 'Fake (${_fakeDevices.length})'),
            Tab(text: '${AppLang.instance.t('requestsTab')} (${_pendingRequests.length})'),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PhotonColors.accent))
          : TabBarView(controller: _tabCtrl, children: [
              _buildLinkedTab(),
              _buildFakeTab(),
              _buildRequestsTab(),
            ]),
    );
  }

  Widget _buildLinkedTab() {
    final linked = _linkedDevices;
    if (linked.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.devices_outlined, color: PhotonColors.textDim, size: 48),
          const SizedBox(height: 16),
          Text(AppLang.instance.t('noLinkedDevices'), style: TextStyle(color: PhotonColors.textDim, fontSize: 15)),
          const SizedBox(height: 8),
          Text(AppLang.instance.t('linkedDevicesHint'),
              textAlign: TextAlign.center, style: PText.small),
        ]),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: linked.length,
      itemBuilder: (_, i) {
        final d = linked[i];
        return _deviceCard(d, actions: [
          _actionBtn(Icons.visibility_outlined, AppLang.instance.t('watch'), PhotonColors.accent, () => _viewActivities(d)),
          _actionBtn(Icons.logout_outlined, AppLang.instance.t('kickShort'), PhotonColors.danger, () => _kickDevice(d)),
        ]);
      },
    );
  }

  Widget _buildFakeTab() {
    final fakes = _fakeDevices;
    if (fakes.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_outlined, color: PhotonColors.textDim, size: 48),
          const SizedBox(height: 16),
          Text(AppLang.instance.t('noFakeAccounts'), style: TextStyle(color: PhotonColors.textDim, fontSize: 15)),
          const SizedBox(height: 8),
          Text(AppLang.instance.t('fakeAccountsHint'),
              textAlign: TextAlign.center, style: PText.small),
        ]),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: fakes.length,
      itemBuilder: (_, i) {
        final d = fakes[i];
        return _deviceCard(d, showFakeBadge: true, actions: [
          _actionBtn(Icons.visibility_outlined, AppLang.instance.t('watch'), PhotonColors.accent, () => _viewActivities(d)),
          _actionBtn(d.isMod ? Icons.remove_moderator_outlined : Icons.admin_panel_settings_outlined, d.isMod ? AppLang.instance.t('modRemove') : AppLang.instance.t('giveMod'), PhotonColors.accent2, () => _giveModToFake(d)),
          _actionBtn(Icons.block_outlined, AppLang.instance.t('block'), PhotonColors.danger, () => _banFake(d)),
        ]);
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_pendingRequests.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.notifications_none_outlined, color: PhotonColors.textDim, size: 48),
          const SizedBox(height: 16),
          Text(AppLang.instance.t('noPendingRequestsShort'), style: TextStyle(color: PhotonColors.textDim, fontSize: 15)),
        ]),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingRequests.length,
      itemBuilder: (_, i) {
        final req = _pendingRequests[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PhotonColors.panel,
            border: Border.all(color: PhotonColors.accent2.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.phone_android_outlined, color: PhotonColors.accent2, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(req.requesterName, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.bold, fontSize: 15))),
            ]),
            const SizedBox(height: 8),
            Text(AppLang.instance.t('deviceWantsToConnect'), style: PText.small),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                style: photonPrimaryButtonStyle(),
                icon: const Icon(Icons.check_outlined, size: 16),
                label: Text(AppLang.instance.t('approveSendCode')),
                onPressed: () => _approveRequest(req),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                style: photonDangerButtonStyle(),
                icon: const Icon(Icons.close_outlined, size: 16),
                label: Text(AppLang.instance.t('rejectFake')),
                onPressed: () => _rejectRequest(req),
              )),
            ]),
          ]),
        );
      },
    );
  }

  Widget _deviceCard(LinkedDevice d, {List<Widget> actions = const [], bool showFakeBadge = false}) {
    final date = DateTime.fromMillisecondsSinceEpoch(d.linkedAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PhotonColors.panel,
        border: Border.all(color: d.isFake ? PhotonColors.danger.withOpacity(0.4) : PhotonColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(d.isFake ? Icons.warning_outlined : Icons.phone_android_outlined, color: d.isFake ? PhotonColors.danger : PhotonColors.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(d.name, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.bold, fontSize: 15))),
          if (showFakeBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: PhotonColors.danger, borderRadius: BorderRadius.circular(8)),
              child: const Text('FAKE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          if (d.isMod)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: PhotonColors.accent2, borderRadius: BorderRadius.circular(8)),
              child: const Text('MOD', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
        ]),
        const SizedBox(height: 4),
        Text('${AppLang.instance.t('connectedAtLabel')} ${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
            style: PText.meta),
        Text('${AppLang.instance.t('activityLabel')} ${d.activities.length} ${AppLang.instance.t('recordsSuffix')}', style: PText.meta),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class DeviceActivityScreen extends StatefulWidget {
  final LinkedDevice device;
  final String serverUrl;
  final String ownerFipId;
  const DeviceActivityScreen({super.key, required this.device, required this.serverUrl, required this.ownerFipId});

  @override
  State<DeviceActivityScreen> createState() => _DeviceActivityScreenState();
}

class _DeviceActivityScreenState extends State<DeviceActivityScreen> {
  List<DeviceActivity> _activities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final serverActivities = await PhotonApi.getDeviceActivities(widget.serverUrl, widget.ownerFipId, widget.device.deviceId);
    final local = widget.device.activities;
    final remote = serverActivities.map((m) => DeviceActivity.fromJson(m)).toList();
    final all = [...local, ...remote];
    all.sort((a, b) => b.ts.compareTo(a.ts));
    if (mounted) setState(() { _activities = all; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.device.name} Aktiviteleri')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PhotonColors.accent))
          : _activities.isEmpty
              ? Center(child: Text(AppLang.instance.t('noActivity'), style: TextStyle(color: PhotonColors.textDim)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _activities.length,
                  itemBuilder: (_, i) {
                    final a = _activities[i];
                    final date = DateTime.fromMillisecondsSinceEpoch(a.ts);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: PhotonColors.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: PhotonColors.line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(_iconForAction(a.action), color: PhotonColors.accent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.action, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w600, fontSize: 13))),
                          Text('${date.hour}:${date.minute.toString().padLeft(2, '0')}', style: PText.meta),
                        ]),
                        if (a.detail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(a.detail, style: PText.small),
                          ),
                      ]),
                    );
                  },
                ),
    );
  }

  IconData _iconForAction(String action) {
    if (action.contains('mesaj') || action.contains('message')) return Icons.chat_outlined;
    if (action.contains('giriş') || action.contains('login')) return Icons.login_outlined;
    if (action.contains('kişi') || action.contains('contact')) return Icons.person_add_outlined;
    if (action.contains('grup') || action.contains('group')) return Icons.group_outlined;
    return Icons.info_outline;
  }
}
