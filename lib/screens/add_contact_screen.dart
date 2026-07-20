import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'qr_scan_screen.dart';
import '../fip.dart';
import '../photon_api.dart';
import '../local_store.dart';
import '../theme.dart';
import '../i18n.dart';

class AddContactScreen extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;

  const AddContactScreen({super.key, required this.identity, required this.displayName, required this.myServerUrl});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _addrCtrl = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _addrCtrl.dispose();
    super.dispose();
  }

  void _showMyQr() {
    showModalBottomSheet(
      context: context,
      backgroundColor: PhotonColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLang.instance.t('myQrCode'), style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: widget.identity.code, size: 200),
            ),
            const SizedBox(height: 16),
            Text(widget.identity.code,
              style: TextStyle(color: PhotonColors.accent, fontSize: 28, fontFamily: 'monospace', letterSpacing: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(AppLang.instance.t('qrHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: PhotonColors.textDim, fontSize: 12)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final code = _addrCtrl.text.trim();

    if (code.length != 5 || !RegExp(r'^\d{5}$').hasMatch(code)) {
      setState(() => _error = AppLang.instance.t('codeMustBe5'));
      return;
    }

    if (code == widget.identity.code) {
      setState(() => _error = AppLang.instance.t('thatIsYourCode'));
      return;
    }

    setState(() { _sending = true; _error = null; });

    try {
      // Bridge'den koda karşılık gelen sunucuyu bul
      final lookup = await PhotonApi.lookupByCodeFromBridge(code);
      if (lookup == null) {
        if (mounted) setState(() {
          _sending = false;
          _error = AppLang.instance.t('noActiveUserWithCode');
        });
        return;
      }

      final targetServerUrl = lookup['serverUrl'] as String;
      final targetFipId = lookup['fipId'] as String;
      final targetName = (lookup['name'] as String?) ?? AppLang.instance.t('unknown');

      await PhotonApi.sendFriendRequest(
        toServerUrl: targetServerUrl,
        toFipId: targetFipId,
        fromFipId: widget.identity.fipId,
        fromCode: widget.identity.code,
        fromName: widget.displayName,
        fromServerUrl: widget.myServerUrl,
      );

      if (!mounted) return;
      Navigator.pop(
        context,
        Contact(fipId: targetFipId, name: targetName, code: code, serverUrl: targetServerUrl, status: 'pending_out'),
      );
    } catch (e) {
      if (mounted) setState(() { _sending = false; _error = '${AppLang.instance.t('inviteFailed')}: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLang.instance.t('addContact')),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: AppLang.instance.t('myQrTooltip'),
            onPressed: () => _showMyQr(),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: AppLang.instance.t('scanFriendQr'),
            onPressed: () async {
              final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
              if (code != null && mounted) {
                _addrCtrl.text = code;
                setState(() {});
                _send();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: PhotonColors.panel,
            border: Border.all(color: PhotonColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLang.instance.t('friendCode5Digit'),
                style: TextStyle(color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addrCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 5,
                style: TextStyle(
                  color: PhotonColors.accent,
                  fontSize: 22,
                  fontFamily: 'monospace',
                  letterSpacing: 8,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '• • • • •',
                  hintStyle: TextStyle(color: Color(0xFF5C6E6B), fontSize: 22, letterSpacing: 8),
                  counterText: '',
                  filled: true,
                  fillColor: PhotonColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: PhotonColors.line),
                  ),
                ),
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text(
                AppLang.instance.t('friendCodeHint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: PhotonColors.textDim, fontSize: 11, height: 1.6),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: PhotonColors.danger, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: photonGhostButtonStyle(),
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLang.instance.t('cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: photonPrimaryButtonStyle(),
                      onPressed: (_addrCtrl.text.trim().length == 5 && !_sending) ? _send : null,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06251A)),
                            )
                          : Text(AppLang.instance.t('sendInvite')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
