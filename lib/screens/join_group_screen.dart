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
      setState(() => _showServer = false);
    } else {
      final code = _extractCode(val);
      if (code.length == 7) {
        setState(() => _showServer = true);
      } else {
        setState(() => _showServer = false);
      }
    }
  }

  Future<void> _join() async {
    final code   = _extractCode(_inputCtrl.text);
    final server = _extractServer(_inputCtrl.text).isNotEmpty
        ? _extractServer(_inputCtrl.text)
        : _serverCtrl.text.trim();

    if (code.length != 7) {
      setState(() => _error = 'Grup kodu 7 haneli olmalıdır');
      return;
    }
    if (server.isEmpty || !server.startsWith('http')) {
      setState(() => _error = 'Grup sahibinin sunucu adresi eksik');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final data = await KnkApi.getGroupByCode(server, code);
      if (data == null) {
        setState(() { _error = 'Grup bulunamadı. Davet linkini kontrol et.'; _loading = false; });
        return;
      }
      final groupId   = data['groupId'] as String;
      final groupName = data['name']    as String? ?? 'Grup';
      final groupDesc = data['description'] as String? ?? '';
      await KnkApi.sendGroupJoinRequest(server, groupId,
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
      setState(() { _error = 'Hata: $e'; _loading = false; });
    }
  }

  bool get _canJoin {
    final code   = _extractCode(_inputCtrl.text);
    final server = _extractServer(_inputCtrl.text).isNotEmpty
        ? _extractServer(_inputCtrl.text)
        : _serverCtrl.text.trim();
    return code.length == 7 && server.startsWith('http') && !_loading;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gruba Katıl')),
      backgroundColor: KnkColors.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
              child: Text(
                'Grup sahibinin paylaştığı davet linkini yapıştır — otomatik tanınır.\n\nDavet linki yoksa 7 haneli grup kodunu yaz.',
                style: TextStyle(color: KnkColors.text, fontSize: 13, height: 1.6),
              ),
            ),
            const SizedBox(height: 20),

            Text('DAVET LİNKİ VEYA GRUP KODU',
              style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            TextField(
              controller: _inputCtrl,
              keyboardType: TextInputType.text,
              maxLength: 300,
              style: TextStyle(color: KnkColors.accent, fontSize: 14, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'photon://1234567@https://… veya sadece 1234567',
                hintStyle: TextStyle(color: KnkColors.textDim, fontSize: 11),
                counterText: '',
                filled: true, fillColor: KnkColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.accent)),
              ),
              autocorrect: false,
              onChanged: _onInputChanged,
            ),

            if (_showServer) ...[
              const SizedBox(height: 16),
              Text('GRUP SAHİBİNİN SUNUCU ADRESİ',
                style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              TextField(
                controller: _serverCtrl,
                style: TextStyle(color: KnkColors.text, fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'https://sunucu.onrender.com',
                  hintStyle: TextStyle(color: KnkColors.textDim, fontSize: 12),
                  filled: true, fillColor: KnkColors.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.accent)),
                ),
                autocorrect: false,
                onChanged: (_) => setState(() => _error = null),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: KnkColors.danger, fontSize: 12), maxLines: 3),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: knkPrimaryButtonStyle(),
                onPressed: _canJoin ? _join : null,
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
