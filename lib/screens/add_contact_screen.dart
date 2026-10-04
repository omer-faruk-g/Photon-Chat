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
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.s3, 0, Space.s3, Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLang.instance.t('myQrCode'), style: PText.label),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(PhotonRadius.card)),
              child: QrImageView(data: widget.identity.code, size: 200),
            ),
            const SizedBox(height: 16),
            Text(widget.identity.code,
              style: PText.h1.merge(PText.tabular).copyWith(color: PhotonColors.accent, fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600, letterSpacing: 8)),
            const SizedBox(height: 8),
            Text(AppLang.instance.t('qrHint'),
              textAlign: TextAlign.center,
              style: PText.small),
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
            icon: const Icon(Icons.qr_code_outlined),
            tooltip: AppLang.instance.t('myQrTooltip'),
            onPressed: () => _showMyQr(),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            tooltip: AppLang.instance.t('scanFriendQr'),
            onPressed: () async {
              final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScanScreen(mode: QrScanMode.contact)));
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
        padding: const EdgeInsets.fromLTRB(Space.s3, Space.s4, Space.s3, Space.s4),
        child: ContentWidth(
          max: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trUpper(AppLang.instance.t('friendCode5Digit')), style: PText.label),
              const SizedBox(height: Space.s2),
              TextField(
                controller: _addrCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 5,
                style: PText.display.merge(PText.tabular).copyWith(color: PhotonColors.accent, fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600, letterSpacing: 16),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '00000',
                  hintStyle: PText.display.merge(PText.tabular).copyWith(color: PhotonColors.line, fontFamily: PhotonFonts.body, letterSpacing: 16),
                  counterText: '',
                  errorText: _error,
                  errorMaxLines: 3,
                  contentPadding: const EdgeInsets.symmetric(vertical: Space.s3),
                ),
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) { if (_addrCtrl.text.trim().length == 5 && !_sending) _send(); },
              ),
              const SizedBox(height: Space.s2),
              Text(AppLang.instance.t('friendCodeHint'), style: PText.small),
              const SizedBox(height: Space.s4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLang.instance.t('cancel')),
                    ),
                  ),
                  const SizedBox(width: Space.s1),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (_addrCtrl.text.trim().length == 5 && !_sending) ? _send : null,
                      child: _sending
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: PhotonColors.onAccent))
                          : Text(AppLang.instance.t('sendInvite')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s4),
              HoverCard(
                onTap: _showMyQr,
                child: Row(children: [
                  Icon(Icons.qr_code_outlined, color: PhotonColors.accent),
                  const SizedBox(width: Space.s2),
                  Expanded(child: Text(trUpper(AppLang.instance.t('myQrCode')), style: PText.label.copyWith(color: PhotonColors.text))),
                  Text(widget.identity.code, style: PText.title.merge(PText.tabular).copyWith(color: PhotonColors.accent, letterSpacing: 2)),
                  const SizedBox(width: Space.s1),
                  Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
