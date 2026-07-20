import 'package:flutter/material.dart';
import '../device_manager.dart';
import '../photon_api.dart';
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
    setState(() => _activeCode = code);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PhotonColors.panel,
        title: Text('Doğrulama Kodu (Deneme $attempt/3)', style: TextStyle(color: PhotonColors.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Bu $codeLength haneli kodu diğer cihaza gir:', style: TextStyle(color: PhotonColors.textDim, fontSize: 13)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: PhotonColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PhotonColors.accent, width: 2),
            ),
            child: Text(code, style: TextStyle(color: PhotonColors.accent, fontSize: codeLength > 12 ? 20 : 28, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 12),
          Text('${req.requesterName} bağlanmaya çalışıyor', style: TextStyle(color: PhotonColors.textDim, fontSize: 12)),
          if (attempt > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('⚠️ Deneme $attempt — ${attempt == 3 ? "Son şans!" : "Bir sonraki 15 haneli olacak"}', style: TextStyle(color: Colors.orange, fontSize: 11)),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); _load(); },
            child: Text('Tamam', style: TextStyle(color: PhotonColors.accent)),
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
        title: Text('Cihazı At', style: TextStyle(color: PhotonColors.text)),
        content: Text(
          '${device.name} cihazını atmak istediğine emin misin?\n\nAtılan cihaz bir daha bu servera bağlanamaz.',
          style: TextStyle(color: PhotonColors.textDim, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Vazgeç', style: TextStyle(color: PhotonColors.textDim))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('At', style: TextStyle(color: PhotonColors.danger))),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${device.name} banlandı'), backgroundColor: PhotonColors.danger));
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
        title: const Text('Cihaz Yönetimi'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: PhotonColors.accent,
          unselectedLabelColor: PhotonColors.textDim,
          indicatorColor: PhotonColors.accent,
          tabs: [
            Tab(text: 'Cihazlar (${_linkedDevices.length})'),
            Tab(text: 'Fake (${_fakeDevices.length})'),
            Tab(text: 'İstekler (${_pendingRequests.length})'),
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
          Icon(Icons.devices, color: PhotonColors.textDim, size: 48),
          const SizedBox(height: 16),
          Text('Bağlı yan cihaz yok', style: TextStyle(color: PhotonColors.textDim, fontSize: 14)),
          const SizedBox(height: 8),
          Text('Başka bir cihaz aynı server URL\'sine bağlanmaya çalıştığında burada görünecek.',
              textAlign: TextAlign.center, style: TextStyle(color: PhotonColors.textDim, fontSize: 12)),
        ]),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: linked.length,
      itemBuilder: (_, i) {
        final d = linked[i];
        return _deviceCard(d, actions: [
          _actionBtn(Icons.visibility, 'İzle', PhotonColors.accent, () => _viewActivities(d)),
          _actionBtn(Icons.logout, 'At', PhotonColors.danger, () => _kickDevice(d)),
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
          Icon(Icons.shield, color: PhotonColors.textDim, size: 48),
          const SizedBox(height: 16),
          Text('Fake hesap yok', style: TextStyle(color: PhotonColors.textDim, fontSize: 14)),
          const SizedBox(height: 8),
          Text('Yanlış kod giren veya reddedilen cihazlar burada FAKE olarak görünür.',
              textAlign: TextAlign.center, style: TextStyle(color: PhotonColors.textDim, fontSize: 12)),
        ]),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: fakes.length,
      itemBuilder: (_, i) {
        final d = fakes[i];
        return _deviceCard(d, showFakeBadge: true, actions: [
          _actionBtn(Icons.visibility, 'İzle', PhotonColors.accent, () => _viewActivities(d)),
          _actionBtn(d.isMod ? Icons.remove_moderator : Icons.admin_panel_settings, d.isMod ? 'MOD Kaldır' : 'MOD Ver', Colors.amber, () => _giveModToFake(d)),
          _actionBtn(Icons.block, 'Banla', PhotonColors.danger, () => _banFake(d)),
        ]);
      },
    );
  }

  Widget _buildRequestsTab() {
    if (_pendingRequests.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.notifications_none, color: PhotonColors.textDim, size: 48),
          const SizedBox(height: 16),
          Text('Bekleyen istek yok', style: TextStyle(color: PhotonColors.textDim, fontSize: 14)),
        ]),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pendingRequests.length,
      itemBuilder: (_, i) {
        final req = _pendingRequests[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PhotonColors.panel,
            border: Border.all(color: Colors.orange.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.phone_android, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(req.requesterName, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.bold, fontSize: 14))),
            ]),
            const SizedBox(height: 8),
            Text('Bu cihaz senin serverına bağlanmak istiyor.', style: TextStyle(color: PhotonColors.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                style: photonPrimaryButtonStyle(),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Onayla (Kod Gönder)'),
                onPressed: () => _approveRequest(req),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                style: photonDangerButtonStyle(),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Reddet (FAKE)'),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PhotonColors.panel,
        border: Border.all(color: d.isFake ? PhotonColors.danger.withOpacity(0.4) : PhotonColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(d.isFake ? Icons.warning : Icons.phone_android, color: d.isFake ? PhotonColors.danger : PhotonColors.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(d.name, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.bold, fontSize: 14))),
          if (showFakeBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: PhotonColors.danger, borderRadius: BorderRadius.circular(4)),
              child: const Text('FAKE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          if (d.isMod)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
              child: const Text('MOD', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
        ]),
        const SizedBox(height: 4),
        Text('Bağlandı: ${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
            style: TextStyle(color: PhotonColors.textDim, fontSize: 11)),
        Text('Aktivite: ${d.activities.length} kayıt', style: TextStyle(color: PhotonColors.textDim, fontSize: 11)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              ? Center(child: Text('Henüz aktivite yok', style: TextStyle(color: PhotonColors.textDim)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _activities.length,
                  itemBuilder: (_, i) {
                    final a = _activities[i];
                    final date = DateTime.fromMillisecondsSinceEpoch(a.ts);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: PhotonColors.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: PhotonColors.line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(_iconForAction(a.action), color: PhotonColors.accent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.action, style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w600, fontSize: 13))),
                          Text('${date.hour}:${date.minute.toString().padLeft(2, '0')}', style: TextStyle(color: PhotonColors.textDim, fontSize: 11)),
                        ]),
                        if (a.detail.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(a.detail, style: TextStyle(color: PhotonColors.textDim, fontSize: 12)),
                          ),
                      ]),
                    );
                  },
                ),
    );
  }

  IconData _iconForAction(String action) {
    if (action.contains('mesaj') || action.contains('message')) return Icons.chat;
    if (action.contains('giriş') || action.contains('login')) return Icons.login;
    if (action.contains('kişi') || action.contains('contact')) return Icons.person_add;
    if (action.contains('grup') || action.contains('group')) return Icons.group;
    return Icons.info_outline;
  }
}
