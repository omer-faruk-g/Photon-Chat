import 'package:flutter/material.dart';
import '../fip.dart';
import '../local_store.dart';
import '../photon_api.dart';
import '../theme.dart';
import '../i18n.dart';
import 'qr_scan_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  const JoinGroupScreen({super.key, required this.identity, required this.displayName, required this.myServerUrl});
  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _inputCtrl  = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _loading = false;
  bool _showServer = false;
  String? _error;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  String _extractCode(String val) {
    var s = val.trim();
    if (s.startsWith('photon://')) s = s.substring(9);
    final at = s.indexOf('@');
    if (at > 0) return s.substring(0, at);
    return s;
  }

  String _extractServer(String val) {
    var s = val.trim();
    if (s.startsWith('photon://')) s = s.substring(9);
    final at = s.indexOf('@');
    if (at > 0) return s.substring(at + 1);
    return '';
  }

  void _onInputChanged(String val) {
    setState(() => _error = null);
    final server = _extractServer(val);
    if (server.startsWith('http')) {
      _serverCtrl.text = server;
    }
    // Server field is now optional — bridge auto-resolves — so we never
    // force-open it. User can still open it via the "advanced" toggle.
    setState(() {});
  }

  Future<void> _join() async {
    final code = _extractCode(_inputCtrl.text);
    var server = _extractServer(_inputCtrl.text).isNotEmpty
        ? _extractServer(_inputCtrl.text)
        : _serverCtrl.text.trim();

    if (code.length != 7) {
      setState(() => _error = AppLang.instance.t('groupCode7Required'));
      return;
    }

    setState(() { _loading = true; _error = null; });

    // Try multiple servers in order:
    // 1) explicit server URL if user typed one
    // 2) bridge lookup for the code
    // 3) user's own server (in case the group lives on the same server)
    final candidates = <String>[];
    if (server.startsWith('http')) candidates.add(server);
    final bridgeHit = await PhotonApi.lookupServerOnBridge(code);
    if (bridgeHit != null && !candidates.contains(bridgeHit)) candidates.add(bridgeHit);
    if (widget.myServerUrl.startsWith('http') && !candidates.contains(widget.myServerUrl)) {
      candidates.add(widget.myServerUrl);
    }
    // Also try the bridge itself as a last-resort catch-all
    if (!candidates.contains('https://photon-chat.onrender.com')) {
      candidates.add('https://photon-chat.onrender.com');
    }
    if (candidates.isEmpty) {
      setState(() { _error = AppLang.instance.t('groupNotFound'); _loading = false; });
      return;
    }
    try {
      Map<String, dynamic>? data;
      String? foundServer;
      for (final cand in candidates) {
        try {
          final r = await PhotonApi.getGroupByCode(cand, code);
          if (r != null) { data = r; foundServer = cand; break; }
        } catch (_) {}
      }
      if (data == null || foundServer == null) {
        setState(() { _error = AppLang.instance.t('groupNotFound'); _loading = false; });
        return;
      }
      server = foundServer;
      final groupId   = data['groupId'] as String;
      final groupName = data['name']    as String? ?? AppLang.instance.t('group');
      final groupDesc = data['description'] as String? ?? '';
      await PhotonApi.sendGroupJoinRequest(server, groupId,
        fromFipId:     widget.identity.fipId,
        fromName:      widget.displayName,
        fromServerUrl: widget.myServerUrl,
      );
      final group = Group(
        groupId: groupId, groupCode: code, name: groupName,
        description: groupDesc,
        ownerFipId: data['ownerFipId'] as String? ?? '',
        ownerServerUrl: server, isOwner: false, members: [],
      );
      if (mounted) Navigator.pop(context, group);
    } catch (e) {
      setState(() { _error = '${AppLang.instance.t('error')}: $e'; _loading = false; });
    }
  }

  bool get _canJoin {
    // Server URL is now resolved from the global bridge if the user only
    // provides a code, so a valid 7-digit code alone is enough.
    final code = _extractCode(_inputCtrl.text);
    return code.length == 7 && !_loading;
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => const QrScanScreen(mode: QrScanMode.group),
    ));
    if (scanned == null || !mounted) return;
    // Fill input then auto-attempt join (server URL is inside the QR payload).
    _inputCtrl.text = scanned;
    _onInputChanged(scanned);
    if (_canJoin) await _join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLang.instance.t('joinGroup')),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: AppLang.instance.t('scanGroupQr'),
            onPressed: _scanQr,
          ),
        ],
      ),
      backgroundColor: PhotonColors.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PhotonColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PhotonColors.line),
              ),
              child: Text(
                AppLang.instance.t('joinGroupIntro'),
                style: TextStyle(color: PhotonColors.text, fontSize: 13, height: 1.6),
              ),
            ),
            const SizedBox(height: 20),

            Text(AppLang.instance.t('inviteLinkOrCode'),
              style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            TextField(
              controller: _inputCtrl,
              keyboardType: TextInputType.text,
              maxLength: 300,
              style: TextStyle(color: PhotonColors.accent, fontSize: 14, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: AppLang.instance.t('inviteLinkHint'),
                hintStyle: TextStyle(color: PhotonColors.textDim, fontSize: 11),
                counterText: '',
                filled: true, fillColor: PhotonColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.accent)),
              ),
              autocorrect: false,
              onChanged: _onInputChanged,
            ),

            if (_showServer) ...[
              const SizedBox(height: 16),
              Text(AppLang.instance.t('groupOwnerServer'),
                style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              TextField(
                controller: _serverCtrl,
                style: TextStyle(color: PhotonColors.text, fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: AppLang.instance.t('ownerServerHint'),
                  hintStyle: TextStyle(color: PhotonColors.textDim, fontSize: 12),
                  filled: true, fillColor: PhotonColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.accent)),
                ),
                autocorrect: false,
                onChanged: (_) => setState(() => _error = null),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: PhotonColors.danger, fontSize: 12), maxLines: 3),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: photonPrimaryButtonStyle(),
                onPressed: _canJoin ? _join : null,
                child: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text(AppLang.instance.t('sendJoinRequest')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
