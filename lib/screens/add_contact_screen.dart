import 'package:flutter/material.dart';
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
  final _codeCtrl = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final code = _codeCtrl.text.trim();

    if (code.length != 5) {
      setState(() => _error = 'Kod 5 haneli olmalı');
      return;
    }

    if (code == widget.identity.code) {
      setState(() => _error = 'Bu senin kendi kodun.');
      return;
    }

    setState(() { _sending = true; _error = null; });

    final target = await KnkApi.lookupByCode(widget.myServerUrl, code);
    if (target == null) {
      setState(() {
        _sending = false;
        _error = 'Bu kodla aktif bir kullanıcı bulunamadı.';
      });
      return;
    }

    final targetFipId = target['fipId'] as String;
    final targetName = (target['name'] as String?) ?? 'Bilinmeyen';
    final targetServerUrl = (target['serverUrl'] as String?) ?? widget.myServerUrl;

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
      appBar: AppBar(title: const Text('Kişi Ekle')),
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
                maxLength: 5,
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
                onChanged: (_) => setState(() {}),
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
