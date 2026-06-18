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

  Future<void> _join() async {
    final raw = _ctrl.text.trim();
    final at = raw.indexOf('@');
    if (at < 0) { setState(() => _error = 'Format: GRUPKODU@https://sunucu.onrender.com'); return; }
    final code = raw.substring(0, at);
    final ownerServerUrl = raw.substring(at + 1);
    if (code.length != 7) { setState(() => _error = 'Grup kodu 7 haneli olmalı'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await KnkApi.getGroupByCode(ownerServerUrl, code);
      if (data == null) { setState(() { _error = 'Grup bulunamadı'; _loading = false; }); return; }
      final groupId = data['groupId'] as String;
      final groupName = data['name'] as String? ?? 'Grup';
      await KnkApi.sendGroupJoinRequest(ownerServerUrl, groupId,
        fromFipId: widget.identity.fipId,
        fromName: widget.displayName,
        fromServerUrl: widget.myServerUrl,
      );
      final group = Group(
        groupId: groupId,
        groupCode: code,
        name: groupName,
        ownerFipId: data['ownerFipId'] as String? ?? '',
        ownerServerUrl: ownerServerUrl,
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
            Text('Grup sahibinden aldığın adresi gir.\n\nFormat:  GRUPKODU@https://sunucu.onrender.com', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.7)),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              style: TextStyle(color: KnkColors.text, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Grup Adresi',
                hintText: '1234567@https://sunucu.onrender.com',
                hintStyle: TextStyle(color: KnkColors.textDim, fontSize: 12),
                labelStyle: TextStyle(color: KnkColors.textDim),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(8)),
                errorText: _error,
                errorStyle: TextStyle(color: KnkColors.danger),
              ),
              autocorrect: false,
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
