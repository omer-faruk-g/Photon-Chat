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
    final ready = _codeCtrl.text.trim().length == 5 && !_sending;
    return Scaffold(
      appBar: AppBar(title: const Text('Kişi ekle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s5),
        child: ContentWidth(
          max: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Arkadaşının kodunu yaz.', style: KnkText.h1),
              const SizedBox(height: Space.s3),
              const Text('Kod, arkadaşının ana ekranının en üstünde yazan 5 hanedir. Sunucusunu uygulama kendisi bulur.', style: KnkText.bodyDim),
              const SizedBox(height: Space.s4),
              TextField(
                controller: _codeCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 5,
                onSubmitted: (_) => _send(),
                style: KnkText.code.copyWith(fontSize: 34, letterSpacing: 16),
                decoration: InputDecoration(
                  hintText: '00000',
                  counterText: '',
                  hintStyle: KnkText.code.copyWith(fontSize: 34, letterSpacing: 16, color: KnkColors.line),
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                autocorrect: false,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: Space.s2),
              ElevatedButton.icon(
                onPressed: ready ? _send : null,
                icon: _sending
                    ? const SizedBox(width: Space.s2, height: Space.s2, child: CircularProgressIndicator(strokeWidth: 2, color: KnkColors.onAccent))
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(_sending ? 'Aranıyor…' : 'Davet gönder'),
              ),
              const SizedBox(height: Space.s4),
              const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 18, color: KnkColors.textDim),
                SizedBox(width: Space.s1),
                Expanded(child: Text('Davet, arkadaşın kabul edene kadar listende “onay bekleniyor” olarak görünür.', style: KnkText.small)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
