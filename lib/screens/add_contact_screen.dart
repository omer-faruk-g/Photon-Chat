import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../theme.dart';

class AddContactScreen extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  /// Listede zaten bulunan kişiler (tekrar eklemeyi önlemek için).
  final Set<String> existingFipIds;
  final String? publicKey;

  const AddContactScreen({super.key, required this.identity, required this.displayName, required this.myServerUrl,
      this.existingFipIds = const {}, this.publicKey});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _codeCtrl = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _fail(String msg) {
    if (mounted) setState(() { _sending = false; _error = msg; });
  }

  Future<void> _send() async {
    final code = _codeCtrl.text.trim();
    if (_sending) return;

    if (!RegExp(r'^\d{5}$').hasMatch(code)) {
      setState(() => _error = 'Kod 5 haneli bir sayı olmalı');
      return;
    }

    if (code == widget.identity.code) {
      setState(() => _error = 'Bu senin kendi kodun.');
      return;
    }

    setState(() { _sending = true; _error = null; });

    // Önce kendi sunucumuza bak (arkadaşlar çoğu zaman aynı sunucuyu kullanır),
    // bulunamazsa bridge'den hedefin sunucu URL'sini bul.
    var targetServerUrl = widget.myServerUrl;
    var target = await KnkApi.lookupByCode(targetServerUrl, code);
    if (target == null) {
      final bridged = await KnkApi.lookupServerOnBridge(code);
      if (!mounted) return;
      if (bridged == null) {
        return _fail('Bu kod kayıtlı değil. Karşı taraf uygulamayı açmış olmalı.');
      }
      targetServerUrl = bridged;
      // Hedefin kendi sunucusundan bilgilerini al
      target = await KnkApi.lookupByCode(targetServerUrl, code);
    }
    if (!mounted) return;
    if (target == null) {
      return _fail('Kullanıcı şu an çevrimdışı. Biraz sonra tekrar dene.');
    }

    final targetFipId = target['fipId'] as String?;
    if (targetFipId == null) return _fail('Sunucudan geçersiz yanıt alındı.');
    if (targetFipId == widget.identity.fipId) return _fail('Bu senin kendi kodun.');
    if (widget.existingFipIds.contains(targetFipId)) return _fail('Bu kişi zaten listende.');
    final targetName = (target['name'] as String?) ?? 'Bilinmeyen';
    final targetServer = (target['serverUrl'] as String?);
    if (targetServer != null && targetServer.isNotEmpty) targetServerUrl = targetServer;

    final sent = await KnkApi.sendFriendRequest(
      toServerUrl: targetServerUrl,
      toFipId: targetFipId,
      fromFipId: widget.identity.fipId,
      fromCode: widget.identity.code,
      fromName: widget.displayName,
      fromServerUrl: widget.myServerUrl,
      fromPublicKey: widget.publicKey,
    );

    if (!mounted) return;
    if (!sent) return _fail('Davet gönderilemedi. Bağlantını kontrol edip tekrar dene.');
    Navigator.pop(
      context,
      Contact(fipId: targetFipId, name: targetName, code: code, serverUrl: targetServerUrl, status: 'pending_out',
          publicKey: target['publicKey'] as String?),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kişi Ekle')),
      body: SingleChildScrollView(
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
              const Text(
                'ARKADAŞININ KODU',
                style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 6),
              const Text(
                'Arkadaşının ana ekranında görünen 5 haneli kodu gir.',
                style: TextStyle(color: KnkColors.textDim, fontSize: 11, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 5,
                onSubmitted: (_) => _send(),
                style: const TextStyle(
                  color: KnkColors.accent,
                  fontSize: 22,
                  fontFamily: 'monospace',
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  hintText: '47175',
                  counterText: '',
                  hintStyle: const TextStyle(color: Color(0xFF5C6E6B), fontSize: 22, letterSpacing: 8),
                  filled: true,
                  fillColor: KnkColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: KnkColors.line),
                  ),
                ),
                autocorrect: false,
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: KnkColors.danger, fontSize: 12)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: knkGhostButtonStyle(),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: knkPrimaryButtonStyle(),
                      onPressed: (_codeCtrl.text.trim().length == 5 && !_sending) ? _send : null,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06251A)),
                            )
                          : const Text('Davet gönder'),
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
