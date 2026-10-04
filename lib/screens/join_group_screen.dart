import 'package:flutter/material.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';
import '../e2e.dart';
import '../server_setup_screen.dart' show normalizeServerUrl;

class JoinGroupScreen extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  final Set<String> existingGroupIds;
  const JoinGroupScreen({super.key, required this.identity, required this.displayName, required this.myServerUrl,
      this.existingGroupIds = const {}});
  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _fail(String msg) {
    if (mounted) setState(() { _error = msg; _loading = false; });
  }

  Future<void> _join() async {
    if (_loading) return;
    final raw = _ctrl.text.trim();
    final at = raw.indexOf('@');
    if (at < 0) { setState(() => _error = 'Format: GRUPKODU@https://sunucu.onrender.com'); return; }
    final code = raw.substring(0, at).trim();
    final ownerServerUrl = normalizeServerUrl(raw.substring(at + 1));
    if (!RegExp(r'^\d{7}$').hasMatch(code)) { setState(() => _error = 'Grup kodu 7 haneli bir sayı olmalı'); return; }
    if (ownerServerUrl == null) { setState(() => _error = 'Sunucu adresi geçersiz'); return; }
    setState(() { _loading = true; _error = null; });
    final data = await KnkApi.getGroupByCode(ownerServerUrl, code);
    if (!mounted) return;
    final groupId = data?['groupId'] as String?;
    if (data == null || groupId == null) return _fail('Grup bulunamadı. Adresi kontrol et.');
    if (widget.existingGroupIds.contains(groupId)) return _fail('Bu grup zaten listende.');
    final groupName = data['name'] as String? ?? 'Grup';
    final ownerPublicKey = data['ownerPublicKey'] as String?;
    if (ownerPublicKey == null || ownerPublicKey.isEmpty) {
      return _fail('Bu grup uçtan uca şifrelemeyi desteklemiyor (eski sürümle oluşturulmuş).');
    }
    final myPub = await getMyPublicKeyBase64();
    if (!mounted) return;
    final (token, err) = await KnkApi.sendGroupJoinRequest(ownerServerUrl, groupId,
      fromFipId: widget.identity.fipId,
      fromName: widget.displayName,
      fromServerUrl: widget.myServerUrl,
      fromPublicKey: myPub,
    );
    if (!mounted) return;
    if (token == null) return _fail(err ?? 'Katılma isteği gönderilemedi. Tekrar dene.');
    final ownerFipId = data['ownerFipId'] as String? ?? '';
    final group = Group(
      groupId: groupId,
      groupCode: code,
      name: groupName,
      ownerFipId: ownerFipId,
      ownerServerUrl: ownerServerUrl,
      isOwner: false,
      token: token,
      // Sahibin anahtarı burada sabitlenir; grup anahtarı yalnızca bu anahtarla açılır.
      ownerPublicKey: ownerPublicKey,
      members: [],
    );
    Navigator.pop(context, group);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gruba katıl')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s5),
        child: ContentWidth(
          max: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Grup adresini yapıştır.', style: KnkText.h1),
              const SizedBox(height: Space.s3),
              const Text('Grup kurucusu sana 7 haneli kod ve sunucu adresinden oluşan bir adres verir. Kurucu onaylayınca mesajlar açılır.', style: KnkText.bodyDim),
              const SizedBox(height: Space.s4),
              TextField(
                controller: _ctrl,
                decoration: knkInputDecoration('1234567@https://sunucu.onrender.com', label: 'Grup adresi', error: _error),
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                onSubmitted: (_) => _join(),
              ),
              const SizedBox(height: Space.s2),
              ElevatedButton(
                onPressed: _loading ? null : _join,
                child: _loading
                    ? const SizedBox(height: Space.s2, width: Space.s2, child: CircularProgressIndicator(strokeWidth: 2, color: KnkColors.onAccent))
                    : const Text('Katılma isteği gönder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
