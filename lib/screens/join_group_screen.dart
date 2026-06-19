import 'package:flutter/material.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';

class JoinGroupScreen extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  const JoinGroupScreen({super.key, required this.identity, required this.displayName, required this.myServerUrl});
  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Parse input: accepts
  ///   - 7-digit code alone  (requires ownerServerUrl known via invite link — not possible alone)
  ///   - GRUPKODU@https://sunucu  (legacy full address)
  ///   - photon://GRUPKODU@https://sunucu  (invite link format)
  ({String code, String ownerServerUrl})? _parse(String raw) {
    // Strip photon:// prefix
    var s = raw.trim();
    if (s.startsWith('photon://')) s = s.substring(9);

    final at = s.indexOf('@');
    if (at < 0) return null;

    final code = s.substring(0, at);
    final ownerServerUrl = s.substring(at + 1);
    if (code.length != 7) return null;
    if (!ownerServerUrl.startsWith('http')) return null;
    return (code: code, ownerServerUrl: ownerServerUrl);
  }

  Future<void> _join() async {
    final parsed = _parse(_ctrl.text);
    if (parsed == null) {
      setState(() => _error = 'Davet linkini veya grup adresini tam gir\n(photon://GRUPKODU@https://sunucu)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await KnkApi.getGroupByCode(parsed.ownerServerUrl, parsed.code);
      if (data == null) { setState(() { _error = 'Grup bulunamadı'; _loading = false; }); return; }
      final groupId = data['groupId'] as String;
      final groupName = data['name'] as String? ?? 'Grup';
      await KnkApi.sendGroupJoinRequest(parsed.ownerServerUrl, groupId,
        fromFipId: widget.identity.fipId,
        fromName: widget.displayName,
        fromServerUrl: widget.myServerUrl,
      );
      final group = Group(
        groupId: groupId,
        groupCode: parsed.code,
        name: groupName,
        ownerFipId: data['ownerFipId'] as String? ?? '',
        ownerServerUrl: parsed.ownerServerUrl,
        isOwner: false,
        members: [],
      );
      if (mounted) Navigator.pop(context, group);
    } catch (e) {
      setState(() { _error = 'Hata: $e'; _loading = false; });
    }
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
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KnkColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KnkColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GRUBA KATILMA', style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  Text(
                    'Grup sahibinden davet linkini al ve yapıştır.',
                    style: TextStyle(color: KnkColors.text, fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Davet linki formatı:\nphoton://1234567@https://sunucu.onrender.com',
                    style: TextStyle(color: KnkColors.textDim, fontSize: 11, height: 1.6, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              style: TextStyle(color: KnkColors.accent, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Davet Linki',
                hintText: 'photon://1234567@https://sunucu.onrender.com',
                hintStyle: TextStyle(color: KnkColors.textDim, fontSize: 12),
                labelStyle: TextStyle(color: KnkColors.textDim),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(8)),
                errorText: _error,
                errorMaxLines: 3,
                errorStyle: TextStyle(color: KnkColors.danger),
              ),
              autocorrect: false,
              onChanged: (_) => setState(() => _error = null),
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
