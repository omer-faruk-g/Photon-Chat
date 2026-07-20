import 'package:flutter/material.dart';
import '../device_manager.dart';
import '../photon_api.dart';
import '../theme.dart';
import '../fip.dart';

class DeviceLinkScreen extends StatefulWidget {
  final String serverUrl;
  final String ownerFipId;
  final FipBlock identity;
  final String displayName;
  final VoidCallback onLinked;
  final VoidCallback onFake;

  const DeviceLinkScreen({
    super.key,
    required this.serverUrl,
    required this.ownerFipId,
    required this.identity,
    required this.displayName,
    required this.onLinked,
    required this.onFake,
  });

  @override
  State<DeviceLinkScreen> createState() => _DeviceLinkScreenState();
}

class _DeviceLinkScreenState extends State<DeviceLinkScreen> {
  final _codeCtrl = TextEditingController();
  bool _requestSent = false;
  bool _loading = false;
  bool _verifying = false;
  String? _error;
  int _attempt = 0; // 0=not started, 1=first(9), 2=second(12), 3=third(15)
  bool _permanentFake = false;

  int get _currentCodeLength {
    switch (_attempt) {
      case 1: return 9;
      case 2: return 12;
      case 3: return 15;
      default: return 9;
    }
  }

  int get _maxAttempts => 3;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    setState(() { _loading = true; _error = null; });
    await PhotonApi.sendDeviceLinkRequest(
      widget.serverUrl,
      widget.ownerFipId,
      requesterFipId: widget.identity.fipId,
      requesterName: widget.displayName,
    );
    setState(() { _loading = false; _requestSent = true; _attempt = 1; });
  }

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    final expected = _currentCodeLength;
    if (code.length != expected || !RegExp(r'^\d+$').hasMatch(code)) {
      setState(() => _error = 'Kod $expected haneli olmalı');
      return;
    }
    setState(() { _verifying = true; _error = null; });

    await PhotonApi.submitDeviceLinkCode(
      widget.serverUrl,
      widget.ownerFipId,
      requesterFipId: widget.identity.fipId,
      code: code,
    );

    await Future.delayed(const Duration(seconds: 2));

    final status = await PhotonApi.getDeviceLinkStatus(widget.serverUrl, widget.identity.fipId);
    final result = status?['status'] as String? ?? 'pending';

    setState(() => _verifying = false);

    if (result == 'linked') {
      await DeviceManager.saveDeviceRole('secondary');
      await DeviceManager.saveMainDeviceFip(widget.ownerFipId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Cihaz başarıyla eşleştirildi!'), backgroundColor: PhotonColors.accent),
        );
      }
      widget.onLinked();
    } else {
      if (_attempt >= _maxAttempts) {
        await DeviceManager.saveDeviceRole('fake');
        await DeviceManager.saveMainDeviceFip(widget.ownerFipId);
        setState(() => _permanentFake = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('3 yanlış deneme — kalıcı FAKE olarak işaretlendiniz'), backgroundColor: PhotonColors.danger),
          );
        }
        widget.onFake();
      } else {
        final nextLen = _attempt == 1 ? 12 : 15;
        setState(() {
          _attempt++;
          _codeCtrl.clear();
          _error = 'Kod yanlış! Ana cihazdan $nextLen haneli yeni kod al.';
        });
        await PhotonApi.respondDeviceLink(widget.serverUrl, widget.ownerFipId,
            requesterFipId: widget.identity.fipId, status: 'retry', code: '$_attempt');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      appBar: AppBar(title: const Text('Cihaz Bağlama')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _permanentFake ? _buildPermanentFake() : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.devices_other, color: PhotonColors.accent, size: 48),
                const SizedBox(height: 16),
                Text('Bu Server Zaten Kayıtlı', style: TextStyle(color: PhotonColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  'Bu sunucuda zaten bir hesap mevcut. Yan cihaz olarak bağlanmak için ana cihazdan onay gerekiyor.',
                  style: TextStyle(color: PhotonColors.textDim, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 24),

                if (!_requestSent) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: PhotonColors.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PhotonColors.line),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('NASIL ÇALIŞIR?', style: TextStyle(color: PhotonColors.textDim, fontSize: 10, letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      _stepRow('1', 'Bağlantı isteği gönder'),
                      _stepRow('2', 'Ana cihaz sana doğrulama kodu verecek'),
                      _stepRow('3', 'Kodu buraya gir'),
                      _stepRow('4', 'Kod doğruysa yan cihaz olarak bağlan'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: PhotonColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          Icon(Icons.warning, color: PhotonColors.danger, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text('3 yanlış denemede kalıcı FAKE olarak işaretlenirsin!', style: TextStyle(color: PhotonColors.danger, fontSize: 11))),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: photonPrimaryButtonStyle(),
                      icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.send, size: 18),
                      label: Text(_loading ? 'Gönderiliyor…' : 'Bağlantı İsteği Gönder'),
                      onPressed: _loading ? null : _sendRequest,
                    ),
                  ),
                ],

                if (_requestSent) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: PhotonColors.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PhotonColors.accent.withOpacity(0.3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.check_circle, color: PhotonColors.accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Deneme $_attempt / $_maxAttempts', style: TextStyle(color: PhotonColors.accent, fontWeight: FontWeight.bold))),
                      ]),
                      const SizedBox(height: 12),
                      Text('Ana cihazdan aldığın $_currentCodeLength haneli kodu gir:', style: TextStyle(color: PhotonColors.textDim, fontSize: 13)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codeCtrl,
                        style: TextStyle(color: PhotonColors.text, fontSize: _currentCodeLength > 12 ? 18 : 22, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                        maxLength: _currentCodeLength,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '0' * _currentCodeLength,
                          hintStyle: TextStyle(color: PhotonColors.textDim, fontSize: _currentCodeLength > 12 ? 18 : 22, letterSpacing: 3, fontFamily: 'monospace'),
                          filled: true,
                          fillColor: PhotonColors.bg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: PhotonColors.line)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: PhotonColors.accent, width: 2)),
                          errorText: _error,
                          errorStyle: TextStyle(color: PhotonColors.danger, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _attemptIndicator(),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: photonPrimaryButtonStyle(),
                          onPressed: _verifying ? null : _submitCode,
                          child: _verifying
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Text('Kodu Doğrula'),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _attemptIndicator() {
    return Row(children: List.generate(3, (i) {
      final done = i < _attempt - 1;
      final current = i == _attempt - 1;
      return Expanded(
        child: Container(
          height: 4,
          margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
          decoration: BoxDecoration(
            color: done ? PhotonColors.danger : current ? PhotonColors.accent : PhotonColors.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }));
  }

  Widget _buildPermanentFake() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, color: PhotonColors.danger, size: 64),
        const SizedBox(height: 16),
        Text('Kalıcı FAKE', style: TextStyle(color: PhotonColors.danger, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Text(
          '3 yanlış deneme yaptınız.\nBu cihaz kalıcı olarak FAKE olarak işaretlendi.\nAna hesabın hiçbir yetkisini göremezsiniz.',
          textAlign: TextAlign.center,
          style: TextStyle(color: PhotonColors.textDim, fontSize: 13, height: 1.6),
        ),
      ]),
    );
  }

  Widget _stepRow(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(color: PhotonColors.accent.withOpacity(0.2), shape: BoxShape.circle),
          child: Center(child: Text(num, style: TextStyle(color: PhotonColors.accent, fontSize: 11, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: PhotonColors.text, fontSize: 13))),
      ]),
    );
  }
}
