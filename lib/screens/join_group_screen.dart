import 'package:flutter/material.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';
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
    final (token, err) = await KnkApi.sendGroupJoinRequest(ownerServerUrl, groupId,
      fromFipId: widget.identity.fipId,
      fromName: widget.displayName,
      fromServerUrl: widget.myServerUrl,
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
      members: [],
    );
    Navigator.pop(context, group);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gruba Katıl')),
      backgroundColor: KnkColors.bg,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Grup sahibinden aldığın adresi gir.\n\nFormat:  GRUPKODU@https://sunucu.onrender.com', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.7)),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              style: const TextStyle(color: KnkColors.text, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Grup Adresi',
                hintText: '1234567@https://sunucu.onrender.com',
                hintStyle: const TextStyle(color: KnkColors.textDim, fontSize: 12),
                labelStyle: const TextStyle(color: KnkColors.textDim),
                enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(8)),
                errorText: _error,
                errorStyle: const TextStyle(color: KnkColors.danger),
              ),
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: knkPrimaryButtonStyle(),
                onPressed: _loading ? null : _join,
                child: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Katılma İsteği Gönder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
