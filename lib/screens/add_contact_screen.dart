import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'qr_scan_screen.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../theme.dart';

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

  Future<void> _send() async {
    final code = _addrCtrl.text.trim();

    if (code.length != 5 || !RegExp(r'^\d{5}$').hasMatch(code)) {
      setState(() => _error = 'Kod tam olarak 5 rakamdan oluşmalıdır');
      return;
    }

    if (code == widget.identity.code) {
      setState(() => _error = 'Bu senin kendi kodun.');
      return;
    }

    setState(() { _sending = true; _error = null; });

    // Bridge'den koda karşılık gelen sunucuyu bul
    final lookup = await KnkApi.lookupByCodeFromBridge(code);
    if (lookup == null) {
      setState(() {
        _sending = false;
        _error = 'Bu koda sahip aktif bir kullanıcı bulunamadı.';
      });
      return;
    }

    final targetServerUrl = lookup['serverUrl'] as String;
    final targetFipId = lookup['fipId'] as String;
    final targetName = (lookup['name'] as String?) ?? 'Bilinmeyen';

    await KnkApi.sendFriendRequest(
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kişi Ekle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'QR ile Ekle',
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: KnkColors.panel,
            border: Border.all(color: KnkColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ARKADAŞİNİN 5 HANELİ KODU',
                style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addrCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 5,
                style: TextStyle(
                  color: KnkColors.accent,
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
                  fillColor: KnkColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: KnkColors.line),
                  ),
                ),
                autocorrect: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text(
                'Arkadaşının profilindeki 5 haneli kodu gir. '
                'Davet isteği otomatik olarak onun sunucusuna gönderilir.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KnkColors.textDim, fontSize: 11, height: 1.6),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: KnkColors.danger, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: knkGhostButtonStyle(),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Vazgeç'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: knkPrimaryButtonStyle(),
                      onPressed: (_addrCtrl.text.trim().length == 5 && !_sending) ? _send : null,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06251A)),
                            )
                          : Text('Davet gönder'),
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
