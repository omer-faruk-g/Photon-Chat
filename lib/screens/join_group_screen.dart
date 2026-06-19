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
  final _codeCtrl   = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  /// Davet linkini otomatik parse eder ve alanları doldurur.
  void _onCodeChanged(String val) {
    setState(() => _error = null);
    var s = val.trim();
    if (s.startsWith('photon://')) s = s.substring(9);
    final at = s.indexOf('@');
    if (at > 0) {
      final code = s.substring(0, at);
      final server = s.substring(at + 1);
      if (code.length == 7 && server.startsWith('http')) {
        _codeCtrl.text = code;
        _codeCtrl.selection = TextSelection.collapsed(offset: code.length);
        _serverCtrl.text = server;
        setState(() {});
      }
    }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    final server = _serverCtrl.text.trim();

    if (code.length != 7) {
      setState(() => _error = 'Grup kodu 7 haneli olmalıdır');
      return;
    }
    if (server.isEmpty || !server.startsWith('http')) {
      setState(() => _error = 'Sunucu adresi eksik veya geçersiz');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final data = await KnkApi.getGroupByCode(server, code);
      if (data == null) {
        setState(() { _error = 'Grup bulunamadı. Kodu ve sunucuyu kontrol et.'; _loading = false; });
        return;
      }
      final groupId   = data['groupId'] as String;
      final groupName = data['name']    as String? ?? 'Grup';
      await KnkApi.sendGroupJoinRequest(server, groupId,
        fromFipId:   widget.identity.fipId,
        fromName:    widget.displayName,
        fromServerUrl: widget.myServerUrl,
      );
      final group = Group(
        groupId: groupId, groupCode: code, name: groupName,
        ownerFipId: data['ownerFipId'] as String? ?? '',
        ownerServerUrl: server, isOwner: false, members: [],
      );
      if (mounted) Navigator.pop(context, group);
    } catch (e) {
      setState(() { _error = 'Hata: $e'; _loading = false; });
    }
  }

  bool get _canJoin =>
      _codeCtrl.text.trim().length == 7 &&
      _serverCtrl.text.trim().startsWith('http') &&
      !_loading;

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
            // Bilgi kutusu
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: KnkColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KnkColors.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GRUBA KATILMA', style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                Text('Davet linkini yapıştır — otomatik doldurulur.\nYa da kodu ve sunucu adresini elle gir.',
                  style: TextStyle(color: KnkColors.text, fontSize: 13, height: 1.6)),
              ]),
            ),
            const SizedBox(height: 20),

            // Kod alanı (davet linki yapıştırılabilir)
            Text('GRUP KODU / DAVET LİNKİ',
              style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.text,
              maxLength: 200,
              style: TextStyle(color: KnkColors.accent, fontSize: 15, fontFamily: 'monospace', letterSpacing: 4),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '1234567  veya  photon://1234567@https://…',
                hintStyle: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 0),
                counterText: '',
                filled: true, fillColor: KnkColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.accent)),
              ),
              autocorrect: false,
              onChanged: _onCodeChanged,
            ),
            const SizedBox(height: 16),

            // Sunucu alanı
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
